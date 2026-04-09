module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GlobalPaymentsGateway < Gateway
      class_attribute :actions, :needed_fields

      self.test_url = 'https://certapia.globalpay.com/GlobalPay/transact.asmx/ProcessCreditCard'
      self.live_url = 'https://api.globalpay.com/GlobalPay/transact.asmx/ProcessCreditCard'
      self.homepage_url = 'https://www.globalpayments.com/'
      self.display_name = 'Global Payments'
      self.default_currency = 'USD'
      self.money_format = :dollars
      self.supported_countries = ['US']
      self.supported_cardtypes = %i[visa master american_express discover]
      self.currencies_without_fractions = %w[IDR JPY KRW]

      CURRENCY_DECIMAL_MARK = {
        'USD' => '.',
        'AUD' => '.',
        'BRL' => ',',
        'CAD' => '.',
        'CNY' => '.',
        'DKK' => ',',
        'EUR' => ',',
        'GBP' => '.',
        'HKD' => '.',
        'MYR' => '.',
        'MXN' => '.',
        'NZD' => '.',
        'NOK' => ',',
        'PHP' => '.',
        'SAR' => '.',
        'SGD' => '.',
        'ZAR' => '.',
        'SEK' => ',',
        'CHF' => '.',
        'TWD' => '.',
        'THB' => '.',
        'AED' => '.',
        'VND' => ',',
        'IDR' => '',
        'JPY' => '',
        'KRW' => ''
      }

      self.actions = {
        authorize: 'Auth',
        purchase: 'Sale',
        capture: 'Force',
        void: 'Void',
        refund: 'Return',
        reverse: 'Reversal'
      }

      self.needed_fields = %i[GlobalUserName GlobalPassword TransType CardNum
                              ExpDate MagData NameOnCard Amount InvNum PNRef Zip Street CVNum]

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(money, creditcard, options = {})
        post = {}
        post_ext = {}

        add_amount(money, options, post)
        add_creditcard(post, post_ext, creditcard)
        add_address(post, post_ext, options)
        add_customer_info(post, post_ext, options)
        add_cavv(post_ext, options)

        commit(:authorize, post, post_ext)
      end

      def purchase(money, creditcard, options = {})
        post = {}
        post_ext = {}

        add_amount(money, options, post)
        add_creditcard(post, post_ext, creditcard)
        add_address(post, post_ext, options)
        add_customer_info(post, post_ext, options)
        add_cavv(post_ext, options)

        commit(:purchase, post, post_ext)
      end

      def capture(money, authorization, options = {})
        post = {}
        post_ext = {}

        add_amount(money, options, post)
        pnref, authcode = split_authorization(authorization)
        post[:PNRef] = pnref
        post_ext[:AuthCode] = authcode

        commit(:capture, post, post_ext)
      end

      def void(authorization, options = {})
        post = {}
        post_ext = {}

        pnref, _authcode = split_authorization(authorization)
        post[:PNRef] = pnref

        commit(:void, post, post_ext)
      end

      def refund(money, authorization, options = {})
        post = {}
        post_ext = {}

        add_amount(money, options, post)
        pnref, _authcode = split_authorization(authorization)
        post[:PNRef] = pnref

        commit(:refund, post, post_ext)
      end

      def reverse(money, authorization, creditcard, options = {})
        post = {}
        post_ext = {}

        add_amount(money, options, post)
        pnref, _authcode = split_authorization(authorization)
        post[:PNRef] = pnref

        commit(:reverse, post, post_ext)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(/(CardNum=)[^&]*/, '\1[FILTERED]').
          gsub(/(CVNum=)[^&]*/, '\1[FILTERED]').
          gsub(/(GlobalPassword=)[^&]*/, '\1[FILTERED]').
          gsub(/(MagData=)[^&]*/, '\1[FILTERED]')
      end

      private

      def add_placeholders(post)
        self.needed_fields.each { |field| post[field] = '' }
      end

      def add_creditcard(post, post_ext, creditcard)
        if creditcard.respond_to?(:track_data) && creditcard.track_data.present?
          post[:MagData] = creditcard.track_data
          post[:CardNum] = ''
        else
          raise ArgumentError, 'Missing required parameter: credit_card:number' if creditcard.number.blank?
          raise ArgumentError, 'Missing required parameter: credit_card:month' if creditcard.month.nil?
          raise ArgumentError, 'Missing required parameter: credit_card:year' if creditcard.year.nil?

          post[:CardNum] = creditcard.number
          post[:ExpDate] = expdate(creditcard)
          if creditcard.verification_value?
            post[:CVNum] = creditcard.verification_value
            post_ext[:CVPresence] = 'SUBMITTED'
          else
            post_ext[:CVPresence] = 'NOTSUBMITTED'
          end
        end
        post[:NameOnCard] = creditcard.name if creditcard.name?
      end

      def expdate(creditcard)
        year = sprintf('%.4i', creditcard.year)
        month = sprintf('%.2i', creditcard.month)
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

      def add_cavv(post_ext, options)
        if options[:cavv].present?
          post_ext[:SecureAuthentication] = 'T'
          post_ext[:AuthenticationValue] = options[:cavv]
        end
      end

      def add_amount(money, options, post)
        currency = currency_code(options[:currency] || currency(money))
        raise ArgumentError, 'Unsupported currency type' unless CURRENCY_DECIMAL_MARK.keys.include?(currency)

        post[:Amount] = localized_amount(money, currency).gsub('.', CURRENCY_DECIMAL_MARK[currency])
      end

      def currency_code(currency)
        currency.to_s
      end

      def commit(action, post, post_ext)
        post[:GlobalUserName] = @options[:login]
        post[:GlobalPassword] = @options[:password]
        post[:TransType] = self.actions[action]
        post_ext[:Force] = 'T'
        post_ext[:TermType] = '8BH'

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
        self.needed_fields.each do |field|
          post[field] = '' if post[field].nil?
        end
        ext = post_ext.collect { |key, value| "<#{key}>#{CGI.escape(value.to_s)}</#{key}>" }.join('')
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
