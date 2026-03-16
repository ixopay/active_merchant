module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GlobalCloudPayGateway < Gateway
      self.live_url = 'https://online-safest.com/TPInterface'
      self.test_url = 'https://online-safest.com/TestTPInterface'

      self.default_currency = 'USD'
      self.money_format = :dollars
      self.supported_countries = ['US']
      self.supported_cardtypes = %i[visa master american_express discover]

      self.homepage_url = 'http://www.globalcloudpay.com/'
      self.display_name = 'GlobalCloudPay'

      def initialize(options = {})
        requires!(options, :merchant_id, :acctid, :password)
        super
      end

      def authorize(money, creditcard, options = {})
        post = {}
        post[:merNo] = @options[:merchant_id]
        post[:gatewayNo] = @options[:acctid]
        add_invoice(post, options)
        add_amount(post, money, options)
        add_creditcard(post, creditcard)
        add_customer_data(post, creditcard, options)
        add_address(post, options)

        add_signature(post)
        post[:remark] = options[:description] if options[:description].present?
        post[:returnUrl] = ''
        post[:csid] = options[:custom]

        commit(post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(/(cardNo=)[^&]*/, '\1[FILTERED]').
          gsub(/(cardSecurityCode=)[^&]*/, '\1[FILTERED]').
          gsub(/(password=)[^&]*/, '\1[FILTERED]')
      end

      private

      def add_invoice(post, options)
        post[:orderNo] = options[:order_id]
      end

      def add_amount(post, money, options)
        post[:orderCurrency] = options[:currency] || currency(money)
        post[:orderAmount] = amount(money)
      end

      def add_creditcard(post, creditcard)
        post[:cardNo] = creditcard.number
        post[:cardExpireMonth] = format(creditcard.month, :two_digits)
        post[:cardExpireYear] = format(creditcard.year, :four_digits)
        post[:cardSecurityCode] = creditcard.verification_value
      end

      def add_customer_data(post, creditcard, options)
        post[:issuingBank] = options[:card_issue]
        post[:firstName] = creditcard.first_name || options[:first_name]
        post[:lastName] = creditcard.last_name || options[:last_name]
        post[:email] = options[:email]
        post[:ip] = options[:ip]
      end

      def add_address(post, options)
        if address = (options[:billing_address] || options[:address])
          post[:phone] = address[:phone]
          post[:country] = address[:country]
          post[:state] = address[:state] if address[:state].present?
          post[:city] = address[:city]
          post[:address] = address[:address1]
          post[:zip] = address[:zip]
        end
      end

      def add_signature(post)
        signature = @options[:merchant_id] + @options[:acctid] + post[:orderNo] + post[:orderCurrency] + post[:orderAmount] + post[:firstName] + post[:lastName] + post[:cardNo] + post[:cardExpireYear] + post[:cardExpireMonth] + post[:cardSecurityCode] + post[:email] + @options[:password]
        post[:signInfo] = Digest::SHA256.hexdigest(signature)
      end

      def post_data(parameters = {})
        parameters.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
      end

      def commit(parameters)
        url = test? ? self.test_url : self.live_url

        raw = ssl_post(url, post_data(parameters))
        response = parse(raw)

        message = message_from(response)
        Response.new(success?(response), message, response,
          test: test?,
          authorization: response[:tradeNo]
        )
      end

      def parse(xml)
        reply = {}
        xml = REXML::Document.new(xml)
        if root = REXML::XPath.first(xml, '//respon')
          root.elements.to_a.each do |node|
            reply[node.name.to_sym] = node.text
          end
        end
        reply
      end

      def success?(response)
        response[:orderStatus] != '0'
      end

      def message_from(response)
        response[:orderInfo]
      end
    end
  end
end
