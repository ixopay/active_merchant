module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class DokuGateway < Gateway

      self.test_url = 'https://staging.doku.com/Suite/'
      self.live_url = 'https://pay.doku.com/Suite/'
      self.homepage_url = 'https://www.doku.com/'
      self.display_name = 'Doku'
      self.default_currency = "360"
      self.money_format = :dollars
      self.supported_countries = ['ID']
      self.supported_cardtypes = [:visa, :master]

      ACTION_URL = {
        purchase: 'ReceiveMIP',
        void: 'VoidRequest'
      }.freeze

      def initialize(options = {})
        requires!(options, :mid, :private_key)
        super
      end

      def purchase(money, creditcard, options = {})
        requires!(options, :order_id, :description, :eci)
        post = {}

        add_merchantid(post)
        add_amount(post, money, options)
        post[:TRANSIDMERCHANT] = truncate(options[:order_id], 30)
        add_words(post, "#{post[:AMOUNT]}#{post[:MALLID]}#{@options[:private_key]}#{post[:TRANSIDMERCHANT]}")
        post[:REQUESTDATETIME] = Time.now.strftime("%Y%m%d%H%M%S")
        add_currency(post, money, options)
        post[:SESSIONID] = SecureRandom.hex(16).downcase
        post[:NAME] = truncate(creditcard.name, 50)
        post[:EMAIL] = truncate(options[:email], 100)
        post[:ADDITIONALDATA] = truncate(options[:custom], 1024)
        add_creditcard(post, creditcard, options)
        add_cavv(post, options)
        add_address(post, options)
        post[:BASKET] = truncate(options[:description], 1024)

        commit(:purchase, post)
      end

      def void(authorization, options = {})
        post = {}
        add_merchantid(post)
        _, transid, session = split_authorization(authorization)
        post[:TRANSIDMERCHANT] = transid
        post[:SESSIONID] = session
        add_words(post, "#{post[:MALLID]}#{@options[:private_key]}#{post[:TRANSIDMERCHANT]}#{post[:SESSIONID]}")
        commit(:void, post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((CARDNUMBER=)[^&]*), '\1[FILTERED]').
          gsub(%r((CVV2=)[^&]*), '\1[FILTERED]').
          gsub(%r((WORDS=)[^&]*), '\1[FILTERED]')
      end

      private

      def add_words(post, word_data)
        post[:WORDS] = Digest::SHA1.hexdigest(word_data)
      end

      def add_merchantid(post)
        post[:MALLID] = @options[:mid]
        post[:CHAINMERCHANT] = @options[:subid] || "NA"
        post[:PAYMENTCHANNEL] = "15"
      end

      def add_creditcard(post, creditcard, options)
        raise ArgumentError.new("Missing required parameter: credit_card:number") if creditcard.number.blank?
        raise ArgumentError.new("Missing required parameter: credit_card:month") if creditcard.month.nil?
        raise ArgumentError.new("Missing required parameter: credit_card:year") if creditcard.year.nil?

        post[:CARDNUMBER] = creditcard.number
        post[:EXPIRYDATE] = expdate(creditcard)
        post[:CVV2] = creditcard.verification_value
      end

      def expdate(credit_card)
        "#{format(credit_card.year, :two_digits)}#{format(credit_card.month, :two_digits)}"
      end

      def add_address(post, options)
        if address = options[:billing_address] || options[:address]
          post[:ADDRESS] = truncate(address[:address1], 100) if address[:address1]
          post[:CITY] = truncate(address[:city], 100) if address[:city]
          post[:STATE] = truncate(address[:state], 100) if address[:state]
          post[:COUNTRY] = truncate(address[:country], 2) if address[:country]
          post[:ZIPCODE] = truncate(address[:zip], 10) if address[:zip]
          post[:HOMEPHONE] = truncate(address[:phone], 15)
        end
      end

      def add_cavv(post, options)
        post[:ECI] = options[:eci]
        post[:XID] = truncate(options[:xid], 100)
        post[:AUTHRESRESPONSECODE] = options[:authentication_id]
        post[:CAVVALGORITHM] = options[:authentication_method]
        post[:AUTHRESSTATUS] = options[:authentication_status]
        post[:CAVV] = options[:cavv]
      end

      def add_amount(post, money, options)
        post[:AMOUNT] = amount(money)
        post[:PURCHASEAMOUNT] = amount(money)
      end

      def add_currency(post, money, options)
        currency = currency_code(options[:currency] || currency(money))
        post[:CURRENCY] = currency
        post[:PURCHASECURRENCY] = currency
      end

      def currency_code(currency)
        # Return the currency as-is; Doku uses numeric ISO currency codes
        currency.to_s
      end

      def commit(action, post)
        url = (test? ? self.test_url : self.live_url) + ACTION_URL[action]

        response = parse(ssl_post(url, post_data(post)))

        Response.new(success?(response), message_from(response), response,
          authorization: authorization_from(response),
          test: test?
        )
      end

      def success?(response)
        response[:RESPONSECODE] == '0000' || response[:RESULTMSG] == 'SUCCESS'
      end

      def message_from(response)
        response[:RESULTMSG] || response[:error]
      end

      def authorization_from(response)
        "#{response[:APPROVALCODE]},#{response[:TRANSIDMERCHANT]},#{response[:SESSIONID]}"
      end

      def split_authorization(auth)
        auth.to_s.split(',')
      end

      def post_data(post)
        post.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
      end

      def parse(xml)
        reply = {}
        if xml == "STOP"
          reply[:error] = "Gateway returned STOP error. Contact TokenEx for assistance."
        elsif xml.start_with?('FAILED') || xml.start_with?('SUCCESS')
          reply[:RESULTMSG] = xml
        else
          xml = REXML::Document.new(xml)
          if root = REXML::XPath.first(xml, "//PAYMENT_STATUS")
            root.elements.to_a.each do |node|
              parse_element(reply, node)
            end
          end
        end
        reply
      end

      def parse_element(reply, node)
        if node.has_elements?
          node.elements.each { |e| parse_element(reply, e) }
        else
          reply[node.name.to_sym] = node.text
        end
        reply
      end
    end
  end
end
