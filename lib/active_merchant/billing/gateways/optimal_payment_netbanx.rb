module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class OptimalPaymentNetbanxGateway < Gateway
      self.test_url = 'https://api.test.netbanx.com/cardpayments/v1'
      self.live_url = 'https://api.netbanx.com/cardpayments/v1'

      self.supported_countries = ['US', 'CA']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :solo]
      self.money_format = :cents
      self.homepage_url = 'http://www.optimalpayments.com/'
      self.display_name = 'Optimal Payments NETBANX'

      AVS_CODE_TRANSLATOR = {
        'MATCH'              => 'M',
        'MATCH_ADDRESS_ONLY' => 'A',
        'MATCH_ZIP_ONLY'     => 'Z',
        'NO_MATCH'           => 'N',
        'NOT_PROCESSED'      => 'I'
      }

      CVV_CODE_TRANSLATOR = {
        'MATCH'         => 'M',
        'NO_MATCH'      => 'N',
        'NOT_PROCESSED' => 'P'
      }

      def initialize(options = {})
        requires!(options, :acctid, :password)
        super
      end

      def authorize(money, credit_card, options = {})
        process_auth_purchase(false, money, credit_card, options)
      end

      def purchase(money, credit_card, options = {})
        process_auth_purchase(true, money, credit_card, options)
      end

      def capture(money, authorization, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?
        requires!(options, :order_id)

        post = {}
        post[:merchantRefNum] = truncate(options[:order_id], 255)
        add_amount(post, money)
        commit("auths/#{CGI.escape(authorization)}/settlements", post, options)
      end

      def refund(money, authorization, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?
        requires!(options, :order_id)

        post = {}
        post[:merchantRefNum] = truncate(options[:order_id], 255)
        add_amount(post, money)
        commit("settlements/#{CGI.escape(authorization)}/refunds", post, options)
      end

      def void(authorization, options = {})
        requires!(options, :order_id)

        post = {}
        post[:merchantRefNum] = truncate(options[:order_id], 255)
        commit("auths/#{CGI.escape(authorization)}/voidauths", post, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r("cardNum"\s*:\s*"[^"]*")i, '"cardNum":"[FILTERED]"').
          gsub(%r("cvv"\s*:\s*"[^"]*")i, '"cvv":"[FILTERED]"').
          gsub(%r((Authorization:\s+Basic\s+)\S+)i, '\1[FILTERED]')
      end

      private

      def process_auth_purchase(settle, money, credit_card, options)
        requires!(options, :order_id)

        post = {}
        post[:settleWithAuth] = true if settle
        post[:merchantRefNum] = truncate(options[:order_id], 255)
        add_amount(post, money) unless money == 0
        add_credit_card(post, credit_card)
        add_customer_data(post, credit_card, options)
        add_order_data(post, options)
        add_address(post, :billingDetails, options[:billing_address])
        add_address(post, :shippingDetails, options[:shipping_address])

        commit(money == 0 ? 'verifications' : 'auths', post, options)
      end

      def add_amount(post, money)
        post[:amount] = amount(money)
      end

      def add_customer_data(post, credit_card, options)
        post[:customerIp] = truncate(options[:ip], 39) if options[:ip].present?

        if credit_card.first_name? || credit_card.last_name? || options[:email].present?
          post[:profile] = {}
          post[:profile][:email] = truncate(options[:email], 255) if options[:email].present?
          post[:profile][:firstName] = truncate(credit_card.first_name, 80) if credit_card.first_name?
          post[:profile][:lastName] = truncate(credit_card.last_name, 80) if credit_card.last_name?
        end
      end

      def add_address(post, type, address)
        return if address.nil?
        post[type] = {}
        post[type][:street] = truncate(address[:address1], 50)
        post[type][:street2] = truncate(address[:address2], 50) if type == :billingDetails && address[:address2].present?
        post[type][:city] = truncate(address[:city], 40)
        post[type][:state] = truncate(address[:state], 40)
        post[type][:country] = truncate(address[:country], 2)
        post[type][:zip] = truncate(address[:zip], 10)
        post[type][:phone] = truncate(address[:phone], 40) if type == :billingDetails && address[:phone].present?
      end

      def add_order_data(post, options)
        post[:description] = options[:description] if options[:description].present?
      end

      def add_credit_card(post, credit_card)
        raise ArgumentError, 'Missing required parameter: credit_card' if credit_card.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:number' if credit_card.number.blank?
        raise ArgumentError, 'Missing required parameter: credit_card:month' if credit_card.month.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:year' if credit_card.year.nil?

        post[:card] = {}
        post[:card][:cardNum] = credit_card.number
        post[:card][:cvv] = credit_card.verification_value if credit_card.verification_value?

        post[:card][:cardExpiry] = {}
        post[:card][:cardExpiry][:month] = credit_card.month
        post[:card][:cardExpiry][:year] = credit_card.year

        post[:card][:track1] = credit_card.track_1_data if credit_card.respond_to?(:track_1_data) && credit_card.track_1_data.present?
        post[:card][:track2] = credit_card.track_2_data if credit_card.respond_to?(:track_2_data) && credit_card.track_2_data.present?
      end

      def headers
        {
          'Authorization' => ('Basic ' + Base64.strict_encode64(@options[:password]).chomp),
          'Content-Type' => 'application/json',
          'Accepts' => 'application/json'
        }
      end

      def commit(path, params, options)
        url = "#{test? ? test_url : live_url}/accounts/#{CGI.escape(@options[:acctid])}/#{path}"
        begin
          begin
            raw_response = ssl_post(url, post_data(params), headers)
            response = parse(raw_response)
          rescue ResponseError => e
            response = parse(e.response.body)
          end
        rescue JSON::ParserError
          return unparsable_response(raw_response)
        end

        Response.new(successful?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response),
          avs_result: { code: AVS_CODE_TRANSLATOR[response['avsResponse']] },
          cvv_result: CVV_CODE_TRANSLATOR[response['cvvVerification']]
        )
      end

      def unparsable_response(raw_response)
        message = 'Invalid JSON response received from Optimal Payments.'
        message += " (The raw response returned by the API was #{raw_response.inspect})"
        Response.new(false, message)
      end

      def successful?(response)
        response['error'].nil?
      end

      def message_from(response)
        return response['error']['message'] if response['error']
        response['status']
      end

      def authorization_from(response)
        response['id']
      end

      def parse(body)
        JSON.parse(body)
      end

      def post_data(parameters = {})
        parameters.to_json
      end

      def truncate(value, max_size)
        return nil unless value
        value.to_s[0, max_size]
      end
    end
  end
end
