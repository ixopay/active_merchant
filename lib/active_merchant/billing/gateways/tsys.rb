module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class TsysGateway < Gateway
      self.test_url = 'https://stagegw.transnox.com/servlets/TransNox_API_Server'
      self.live_url = 'https://gateway.transit-pass.com/servlets/TransNox_API_Server'

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :discover]
      self.homepage_url = 'http://www.tsys.com/'
      self.display_name = 'TSYS'
      self.money_format = :cents

      DEVELOPER_ID = '002745G001'

      ACTIONS = {
        auth: 'Auth',
        sale: 'Sale',
        capture: 'Capture',
        void: 'Void',
        refund: 'Return'
      }.freeze

      STANDARD_ERROR_CODE_MAPPING = {
        'FAIL' => STANDARD_ERROR_CODE[:processing_error],
        'DECLINED' => STANDARD_ERROR_CODE[:card_declined]
      }.freeze

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(money, creditcard, options = {})
        create_auth_or_sale_request(:auth, money, creditcard, options)
      end

      def purchase(money, creditcard, options = {})
        create_auth_or_sale_request(:sale, money, creditcard, options)
      end

      def capture(money, authorization, options = {})
        create_capture_or_void(:capture, money, authorization, options)
      end

      def void(authorization, options = {})
        create_capture_or_void(:void, nil, authorization, options)
      end

      def refund(money, authorization, options = {})
        post = {}
        add_amount(post, money, options)

        if options[:credit_card]
          add_payment(post, options[:credit_card], options)
        else
          post[:transactionID] = authorization
        end

        commit(ACTIONS[:refund], post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((\\?"cardNumber\\?":\s*\\?")[^"\\]*), '\1[FILTERED]').
          gsub(%r((\\?"cvv2\\?":\s*\\?")[^"\\]*), '\1[FILTERED]').
          gsub(%r((\\?"transactionKey\\?":\s*\\?")[^"\\]*), '\1[FILTERED]')
      end

      private

      def create_auth_or_sale_request(action, money, creditcard, options = {})
        post = {}

        post[:cardDataSource] = options[:order_source] || 'INTERNET'
        add_amount(post, money, options)
        add_payment(post, creditcard, options)
        add_address(post, options)
        post[:orderNumber] = truncate(options[:order_id], 30) if options[:order_id].present?
        post[:orderNotes] = truncate(options[:description], 256) if options[:description].present?

        commit(ACTIONS[action], post)
      end

      def create_capture_or_void(action, money, authorization, options)
        post = {}

        add_amount(post, money, options) unless money.nil?
        post[:transactionID] = authorization

        commit(ACTIONS[action], post)
      end

      def add_amount(post, money, options = {})
        post[:transactionAmount] = amount(money)
        post[:currencyCode] = options[:currency] if options[:currency].present?
      end

      def add_payment(post, creditcard, options)
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:number' if creditcard.number.blank?
        raise ArgumentError, 'Missing required parameter: credit_card:month' if creditcard.month.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:year' if creditcard.year.nil?

        post[:cardNumber] = creditcard.number
        post[:expirationDate] = format(creditcard.month, :two_digits) + format(creditcard.year, :four_digits)
        post[:cvv2] = creditcard.verification_value if creditcard.verification_value?
        post[:cardHolderName] = creditcard.name if creditcard.name
      end

      def add_address(post, options = {})
        return if options[:billing_address].nil?

        address = options[:billing_address]
        post[:addressLine1] = address[:address1] if address[:address1].present?
        post[:zip] = address[:zip] if address[:zip].present?
      end

      def headers
        {
          'Content-Type' => 'application/json',
          'Accepts' => 'application/json'
        }
      end

      def post_data(action, parameters = {})
        post = {}
        post[action] = {}
        post[action][:deviceID] = @options[:login]
        post[action][:transactionKey] = @options[:password]
        post[action].merge!(parameters)
        post[action][:developerID] = DEVELOPER_ID
        post[action][:authorizationIndicator] = 'PREAUTH' if action == ACTIONS[:auth] || action == ACTIONS[:sale]
        post.to_json
      end

      def commit(action, parameters = {})
        data = post_data(action, parameters)
        url = test? ? self.test_url : self.live_url

        begin
          raw_response = ssl_post(url, data, headers)
          response = parse(raw_response)
        rescue JSON::ParserError
          return unparsable_response(raw_response)
        end

        Response.new(successful?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response),
          avs_result: { code: response['addressVerificationCode'] },
          cvv_result: response['cvvVerificationCode'],
          error_code: standard_error_code(response))
      end

      def parse(body)
        parsed = JSON.parse(body)
        parsed = parsed.values[0] unless parsed.values[0].nil?
        parsed
      end

      def unparsable_response(raw_response)
        message = 'Invalid JSON response received from TSYS.'
        message += " (The raw response returned by the API was #{raw_response.inspect})"
        Response.new(false, message)
      end

      def message_from(response)
        response['responseMessage']
      end

      def authorization_from(response = {})
        response['transactionID']
      end

      def successful?(response)
        response['status'] == 'PASS'
      end

      def standard_error_code(response)
        return unless response['status']

        STANDARD_ERROR_CODE_MAPPING[response['status']]
      end

      def truncate(value, max_size)
        return nil unless value

        value.to_s[0, max_size]
      end
    end
  end
end
