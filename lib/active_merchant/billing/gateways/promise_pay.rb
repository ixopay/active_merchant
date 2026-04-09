module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PromisePayGateway < Gateway
      self.live_url = 'https://secure.api.promisepay.com'
      self.test_url = 'https://test.api.promisepay.com'

      self.supported_countries = ['US', 'AU']
      self.supported_cardtypes = [:visa, :master, :american_express]
      self.default_currency = 'USD'
      self.money_format = :cents
      self.display_name = 'PromisePay'
      self.homepage_url = 'https://www.promisepay.com/'

      def initialize(options = {})
        requires!(options, :login, :private_key)
        super
      end

      def purchase(money, payment_method, options = {})
        requires!(options, :email)

        post = {}
        MultiResponse.run do |r|
          r.process { create_token(payment_method, options) }
          r.process { purchase_with_token(post, money, r.authorization, options) }
        end
      end

      def supports_check?
        true
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(("number"\s*:\s*)"[^"]*"), '\1"[FILTERED]').
          gsub(%r(("cvv"\s*:\s*)"[^"]*"), '\1"[FILTERED]').
          gsub(%r(("account_number"\s*:\s*)"[^"]*"), '\1"[FILTERED]').
          gsub(%r(("routing_number"\s*:\s*)"[^"]*"), '\1"[FILTERED]').
          gsub(%r((Authorization:\s+Basic\s+)\S+), '\1[FILTERED]')
      end

      private

      def create_token(payment_method, options)
        if card_brand(payment_method) == 'check'
          create_bank_token(payment_method, options)
        else
          create_creditcard_token(payment_method, options)
        end
      end

      def create_bank_token(check, options = {})
        post = {}
        post[:bank_name] = check.bank_name.to_s if check.bank_name
        post[:account_name] = check.name.to_s if check.name
        post[:routing_number] = check.routing_number.to_s if check.routing_number
        post[:account_number] = check.account_number.to_s if check.account_number
        post[:account_type] = check.account_type.to_s if check.account_type
        post[:holder_type] = check.account_holder_type.to_s if check.account_holder_type

        address = options[:billing_address] || options[:address]
        if address
          post[:country] = address[:country]
        end

        commit('/bank_accounts', post)
      end

      def create_creditcard_token(creditcard, options = {})
        raise ArgumentError.new('Missing required parameter: credit_card') if creditcard.nil?
        raise ArgumentError.new('Missing required parameter: credit_card:number') if creditcard.number.blank?
        raise ArgumentError.new('Missing required parameter: credit_card:month') if creditcard.month.nil?
        raise ArgumentError.new('Missing required parameter: credit_card:year') if creditcard.year.nil?

        post = {}
        post[:full_name] = "#{creditcard.first_name} #{creditcard.last_name}"
        post[:number] = creditcard.number
        post[:expiry_month] = creditcard.month.to_s
        post[:expiry_year] = creditcard.year.to_s
        post[:cvv] = creditcard.verification_value.to_s

        commit('/card_accounts', post)
      end

      def purchase_with_token(post, money, token, options)
        post[:account_id] = token
        post[:name] = (options[:description] || 'Purchase')
        post[:amount] = amount(money)
        post[:email] = options[:email]

        address = options[:billing_address] || options[:address]
        if address
          post[:zip] = address[:zip]
          post[:country] = address[:country]
        end

        post[:fee_ids] = options[:user_data_1] if options[:user_data_1]
        post[:currency] = options[:currency] if options[:currency]
        post[:retain_account] = false
        post[:device_id] = options[:user_data_2] if options[:user_data_2]
        post[:ip] = options[:ip] if options[:ip]

        commit('/charges', post)
      end

      def parse(response)
        JSON.parse(response)
      end

      def commit(action, params, options = {})
        begin
          response = parse(ssl_post(
            ((test? ? test_url : live_url) + action),
            params.to_json,
            headers
          ))
        rescue ResponseError => e
          response = parse(e.response.body)
        end

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response, params),
          test: test?
        )
      rescue JSON::ParserError
        unparsable_response(response)
      end

      def success_from(response)
        return false if response['errors']

        true
      end

      def message_from(response)
        if response['errors']
          return 'Transaction failed. See Errors for additional details from the gateway' if response['errors'].first.nil?

          "Error: #{response['errors'].first[0]}: #{response['errors'].first[1].join(', ')}"
        elsif response['charges']
          response['charges']['state']
        else
          'completed'
        end
      end

      def authorization_from(response, params)
        return nil unless success_from(response)

        return response['card_accounts']['id'] if response['card_accounts']
        return response['bank_accounts']['id'] if response['bank_accounts']
        return response['charges']['id'] if response['charges']

        nil
      end

      def unparsable_response(raw_response)
        message = 'Error: Invalid JSON response received from PromisePay.'
        message += " (The raw response returned by the API was #{raw_response.inspect})"
        Response.new(false, message)
      end

      def headers
        {
          'Content-Type' => 'application/json',
          'Authorization' => 'Basic ' + Base64.strict_encode64("#{@options[:login]}:#{@options[:private_key]}").strip
        }
      end
    end
  end
end
