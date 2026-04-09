module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaymentBrandsGateway < Gateway
      self.test_url = 'https://fbdev.ministrybrands.com/mb.gateway.qa/api/v2/'
      self.live_url = 'https://gtwy.fdcprocessing.com/api/v2/'

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :jcb, :diners_club]
      self.money_format = :dollars
      self.homepage_url = 'http://www.paymentbrands.com/'
      self.display_name = 'Payment Brands'

      CREDIT_CARD_BRAND = {
        'visa' => 'Visa',
        'master' => 'MasterCard',
        'american_express' => 'AmericanExpress',
        'discover' => 'Discover',
        'jcb' => 'JCB',
        'diners_club' => 'DinersClub'
      }.freeze

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def purchase(amount, payment_method, options = {})
        params = { requestType: 'Sale' }

        add_invoice(params, options)
        add_payment_method(params, payment_method)
        add_address(params, options)
        add_amount(params, amount, options)

        commit('transaction', params, options)
      end

      def authorize(amount, payment_method, options = {})
        params = { requestType: 'Authorization' }

        add_invoice(params, options)
        add_payment_method(params, payment_method)
        add_address(params, options)
        add_amount(params, amount, options)

        commit('transaction', params, options)
      end

      def capture(amount, authorization, options = {})
        params = { requestType: 'Settlement' }

        add_amount(params, amount, options)
        params[:PreviousTransactionId] = authorization

        commit('transaction', params, options)
      end

      def refund(amount, authorization, options = {})
        params = { requestType: 'Credit' }

        add_amount(params, amount, options)
        params[:PreviousTransactionId] = authorization

        commit('transaction', params, options)
      end

      def void(authorization, options = {})
        params = { requestType: 'Void' }

        params[:PreviousTransactionId] = authorization

        commit('transaction', params, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(("cardNumber"\s*:\s*)"[^"]*"), '\1"[FILTERED]"').
          gsub(%r(("cvv2"\s*:\s*)"[^"]*"), '\1"[FILTERED]"').
          gsub(%r(("password"\s*:\s*)"[^"]*"), '\1"[FILTERED]"')
      end

      private

      def add_invoice(params, options)
        params[:transactionDescription] = options[:description] if options[:description]
        params[:clientIpAddress] = options[:ip] if options[:ip]
        params[:customerOrderId] = options[:order_id] if options[:order_id]
        params[:customerReference] = options[:customer] if options[:customer]
        params[:invoiceReferenceNumber] = options[:invoice_number] if options[:invoice_number]
        params[:orderDate] = options[:date] if options[:date]
      end

      def add_payment_method(params, payment_method)
        add_creditcard(params, payment_method)
      end

      def add_creditcard(params, creditcard)
        credit_card = {}

        credit_card[:cardholderName] = creditcard.name
        credit_card[:cardNumber] = creditcard.number
        credit_card[:cardType] = CREDIT_CARD_BRAND[creditcard.brand].to_s
        credit_card[:expirationMonth] = format(creditcard.month, :two_digits).to_s
        credit_card[:expirationYear] = format(creditcard.year, :four_digits).to_s
        credit_card[:cvv2] = creditcard.verification_value if creditcard.verification_value?

        params[:creditcard] = credit_card
      end

      def add_address(params, options)
        address = options[:billing_address]
        return unless address

        billing_address = {}
        billing_address[:addressLine1] = address[:address1] if address[:address1]
        billing_address[:addressLine2] = address[:address2] if address[:address2]
        billing_address[:city] = address[:city] if address[:city]
        billing_address[:state] = address[:state] if address[:state]
        billing_address[:zip] = address[:zip] if address[:zip]
        billing_address[:country] = address[:country] if address[:country]
        billing_address[:firstName] = address[:first_name] if address[:first_name]
        billing_address[:lastName] = address[:last_name] if address[:last_name]

        billing_address[:emailAddress] = options[:email] if options[:email]

        params[:customer] = billing_address
      end

      def add_amount(params, money, options)
        params[:transactionAmount] = amount(money)
      end

      def add_credentials(params)
        creds = {}
        creds[:username] = @options[:login]
        creds[:password] = @options[:password]
        params[:credentials] = creds
      end

      def url
        test? ? test_url : live_url
      end

      def commit(path, params, options)
        post_url = "#{url}#{path}"

        add_credentials(params)

        begin
          body = params.to_json
          response = parse(ssl_post(post_url, body, headers(body)))
        rescue JSON::ParserError
          response = unparsable_response(body)
        end

        Response.new(
          success_from(response),
          handle_message(response, success_from(response)),
          response,
          test: test?,
          authorization: authorization_from(params, response),
          avs_result: { code: response['externalAvsResponseCode'] },
          cvv_result: response['externalCvvResponseCode']
        )
      end

      def success_from(response)
        response['result'].to_s.downcase == 'ok'
      end

      def authorization_from(params, response)
        response['orderId']
      end

      def headers(payload)
        {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      def handle_message(response, success)
        response['resultMessage']
      end

      def parse(body)
        JSON.parse(body)
      end

      def unparsable_response(raw_response)
        message = 'Invalid JSON response received from Payment Brands.'
        message += " (The raw response returned by the API was #{raw_response.inspect})"
        { 'result' => 'error', 'resultMessage' => message }
      end
    end
  end
end
