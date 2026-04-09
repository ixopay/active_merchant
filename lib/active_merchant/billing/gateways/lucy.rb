module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class LucyGateway < Gateway
      class_attribute :actions, :needed_fields

      self.test_url = 'https://cpgtest.cynergydata.com//SmartPayments/transact2.asmx/ProcessCreditCard'
      self.live_url = 'https://payments.cynergydata.com//SmartPayments/transact2.asmx/ProcessCreditCard'
      self.homepage_url = 'https://www.cynergydata.com/'
      self.display_name = 'Lucy'

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.actions = {
        authorize: 'Auth',
        purchase: 'Sale',
        capture: 'Force',
        void: 'Void',
        refund: 'Return',
        reverse: 'Reversal'
      }

      self.needed_fields = [
        :UserName, :Password, :TransType, :CardNum, :ExpDate, :MagData,
        :NameOnCard, :Amount, :InvNum, :PNRef, :Zip, :Street, :CVNum
      ]

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(money, creditcard, options = {})
        post = {}
        post_ext = {}
        add_placeholders(post)

        add_creditcard(post, post_ext, creditcard)
        add_address(post, post_ext, options)
        add_customer_info(post, post_ext, options)

        commit(:authorize, money, post, post_ext)
      end

      def purchase(money, creditcard, options = {})
        post = {}
        post_ext = {}
        add_placeholders(post)

        add_creditcard(post, post_ext, creditcard)
        add_address(post, post_ext, options)
        add_customer_info(post, post_ext, options)

        commit(:purchase, money, post, post_ext)
      end

      def capture(money, authorization, options = {})
        post = {}
        post_ext = {}
        add_placeholders(post)

        pnref, authcode = split_authorization(authorization)
        post[:PNRef] = pnref
        post_ext[:AuthCode] = authcode
        commit(:capture, money, post, post_ext)
      end

      def void(authorization, options = {})
        post = {}
        post_ext = {}
        add_placeholders(post)

        pnref, _ = split_authorization(authorization)
        post[:PNRef] = pnref

        commit(:void, nil, post, post_ext)
      end

      def refund(money, authorization, options = {})
        post = {}
        post_ext = {}
        add_placeholders(post)

        pnref, _ = split_authorization(authorization)
        post[:PNRef] = pnref

        commit(:refund, money, post, post_ext)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((CardNum=)[^&]*)i, '\1[FILTERED]').
          gsub(%r((CVNum=)[^&]*)i, '\1[FILTERED]').
          gsub(%r((Password=)[^&]*)i, '\1[FILTERED]').
          gsub(%r((MagData=)[^&]*)i, '\1[FILTERED]')
      end

      private

      def add_placeholders(post)
        self.needed_fields.each { |field| post[field] = '' }
      end

      def add_creditcard(post, post_ext, creditcard)
        if creditcard.respond_to?(:track_data) && creditcard.track_data.present?
          post[:MagData] = creditcard.track_data
        else
          post[:CardNum] = creditcard.number
          post[:ExpDate] = expdate(creditcard)
          post[:NameOnCard] = creditcard.name if creditcard.name?
          if creditcard.verification_value?
            post[:CVNum] = creditcard.verification_value
            post_ext[:CVPresence] = 3
          else
            post_ext[:CVPresence] = 1
          end
        end
      end

      def expdate(creditcard)
        year  = sprintf("%.4i", creditcard.year)
        month = sprintf("%.2i", creditcard.month)
        "#{month}#{year[2..3]}"
      end

      def add_customer_info(post, post_ext, options)
        post[:InvNum] = options[:order_id] if options[:order_id]
        post_ext[:CustomerID] = options[:customer] if options[:customer]
      end

      def add_address(post, post_ext, options)
        if address = options[:billing_address] || options[:address]
          post[:Zip] = address[:zip] if address[:zip]
          post[:Street] = address[:address1] if address[:address1]
          post_ext[:City] = address[:city] if address[:city]
          post_ext[:BillToState] = address[:state] if address[:state]
        end
      end

      def commit(action, money, post, post_ext)
        post[:UserName] = @options[:login]
        post[:Password] = @options[:password]
        post[:TransType] = self.actions[action]
        post[:Amount] = amount(money) unless money.nil?
        post_ext[:Force] = 'T'

        response = parse(ssl_post(test? ? self.test_url : self.live_url, post_data(post, post_ext)))

        Response.new(success?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response),
          avs_result: { code: response[:GetAVSResult] },
          cvv_result: response[:GetCVResult]
        )
      end

      def success?(response)
        response[:Result] == '0'
      end

      def message_from(response)
        response[:RespMSG]
      end

      def authorization_from(response)
        "#{response[:PNRef]},#{response[:AuthCode]}"
      end

      def split_authorization(auth)
        auth.to_s.split(',')
      end

      def post_data(post, post_ext)
        ext = post_ext.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
        p = post.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
        "#{p}&ExtData=#{ext}"
      end

      def parse(xml)
        reply = {}
        xml = REXML::Document.new(xml)
        if root = REXML::XPath.first(xml, '//Response')
          root.elements.to_a.each do |node|
            parse_element(reply, node)
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
