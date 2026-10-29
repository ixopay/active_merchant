module ActiveMerchant # :nodoc:
  module Billing # :nodoc:
    class AirwallexGateway < Gateway
      self.test_url = 'https://api.sandbox.airwallex.com/api/v1'
      self.live_url = 'https://pci-api.airwallex.com/api/v1'

      # per https://www.airwallex.com/docs/online-payments__overview, cards are accepted in all EU countries
      self.supported_countries = %w[AT AU BE BG CY CZ DE DK EE GR ES FI FR GB HK HR HU IE IT LT LU LV MT NL PL PT RO SE SG SI SK]
      self.default_currency = 'AUD'
      self.supported_cardtypes = %i[visa master american_express]

      self.homepage_url = 'https://airwallex.com/'
      self.display_name = 'Airwallex'

      ENDPOINTS = {
        login: '/authentication/login',
        setup: '/pa/payment_intents/create',
        sale: '/pa/payment_intents/%{id}/confirm',
        capture: '/pa/payment_intents/%{id}/capture',
        refund: '/pa/refunds/create',
        void: '/pa/payment_intents/%{id}/cancel'
      }

      # Provided by Airwallex for testing purposes
      TEST_NETWORK_TRANSACTION_IDS = {
        visa: '123456789012345',
        master: 'MCC123ABC0101'
      }

      # Level 2/Level 3 interchange data, sent as additional_info.enhanced_scheme_data
      # on payment intent creation. Maximum lengths are enforced by Airwallex.
      ENHANCED_SCHEME_DATA_LIMITS = {
        customer_tax_identifier: 13,
        invoice_reference: 17,
        merchant_tax_identifier: 20,
        vat_invoice_reference: 15
      }

      ENHANCED_SCHEME_DATA_AMOUNTS = %i[duty_amount local_tax_amount national_tax_amount total_tax_amount]

      ENHANCED_SCHEME_DATA_PRODUCT_LIMITS = {
        code: 12,
        commodity_code: 12,
        description: 26,
        unit: 12
      }

      ENHANCED_SCHEME_DATA_PRODUCT_AMOUNTS = %i[discount_amount total_amount total_tax_amount unit_price]

      ENHANCED_SCHEME_DATA_ADDRESS_LIMITS = {
        city: 100,
        postcode: 10,
        state: 100,
        street: 1000
      }

      # Airwallex returns the same generic message for every issuer decline, with the
      # reason only in provider_original_response_code. These are the codes produced by
      # the magic amounts in https://www.airwallex.com/docs/payments/test-and-go-live/test-card-numbers
      ISSUER_DECLINE_MESSAGES = {
        '05' => 'Do Not Honor',
        '07' => 'Pick Up Card',
        '14' => 'Invalid Card Number',
        '51' => 'Insufficient Funds',
        '59' => 'Suspected Fraud',
        '100' => 'Deny'
      }

      def initialize(options = {})
        requires!(options, :client_id, :client_api_key)
        @client_id = options[:client_id]
        @client_api_key = options[:client_api_key]
        super
        @access_token = options[:access_token] || setup_access_token
      end

      def purchase(money, card, options = {})
        payment_intent = create_payment_intent(money, options)
        return payment_intent unless payment_intent.success?

        payment_intent_id = payment_intent.params['id']
        post = {
          'request_id' => request_id(options),
          'merchant_order_id' => merchant_order_id(options)
        }
        add_card(post, card, options)
        add_descriptor(post, options)
        add_stored_credential(post, options)
        add_return_url(post, options)
        post['payment_method_options'] = { 'card' => { 'auto_capture' => false } } if authorization_only?(options)

        add_three_ds(post, options)
        commit(:sale, post, payment_intent_id)
      end

      def authorize(money, payment, options = {})
        # authorize is just a purchase w/o an auto capture
        purchase(money, payment, options.merge({ auto_capture: false }))
      end

      def capture(money, authorization, options = {})
        raise ArgumentError, 'An authorization value must be provided.' if authorization.blank?

        post = {
          'request_id' => request_id(options),
          'merchant_order_id' => merchant_order_id(options),
          'amount' => localized_amount(money, options[:currency] || currency(money))
        }
        add_descriptor(post, options)

        commit(:capture, post, authorization)
      end

      def refund(money, authorization, options = {})
        raise ArgumentError, 'An authorization value must be provided.' if authorization.blank?

        post = {}
        post[:amount] = localized_amount(money, options[:currency] || currency(money))
        post[:payment_intent_id] = authorization
        post[:request_id] = request_id(options)
        post[:merchant_order_id] = merchant_order_id(options)

        commit(:refund, post)
      end

      def void(authorization, options = {})
        raise ArgumentError, 'An authorization value must be provided.' if authorization.blank?

        post = {}
        post[:request_id] = request_id(options)
        post[:merchant_order_id] = merchant_order_id(options)
        add_descriptor(post, options)

        commit(:void, post, authorization)
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(/(\\\"number\\\":\\\")\d+/, '\1[REDACTED]').
          gsub(/(\\\"cvc\\\":\\\")\d+/, '\1[REDACTED]')
      end

      private

      def request_id(options)
        options[:request_id] || generate_uuid
      end

      def merchant_order_id(options)
        options[:merchant_order_id] || options[:order_id] || generate_uuid
      end

      def add_return_url(post, options)
        post[:return_url] = options[:return_url] if options[:return_url]
      end

      def generate_uuid
        SecureRandom.uuid
      end

      def setup_access_token
        token_headers = {
          'Content-Type' => 'application/json',
          'x-client-id' => @client_id,
          'x-api-key' => @client_api_key
        }

        begin
          raw_response = ssl_post(build_request_url(:login), nil, token_headers)
        rescue ResponseError => e
          raise OAuthResponseError.new(e)
        else
          response = JSON.parse(raw_response)
          if (token = response['token'])
            token
          else
            oauth_response = Response.new(false, response['message'])
            raise OAuthResponseError.new(oauth_response)
          end
        end
      end

      def build_request_url(action, id = nil)
        base_url = (test? ? test_url : live_url)
        endpoint = ENDPOINTS[action].to_s
        endpoint = id.present? ? endpoint % { id: } : endpoint
        base_url + endpoint
      end

      def add_referrer_data(post, options)
        post[:referrer_data] = options[:referrer_data] || { type: 'ixopay' }
      end

      def create_payment_intent(money, options = {})
        post = {}
        add_invoice(post, money, options)
        add_order(post, options)
        post[:request_id] = "#{request_id(options)}_setup"
        post[:merchant_order_id] = merchant_order_id(options)
        add_referrer_data(post, options)
        add_descriptor(post, options)
        add_enhanced_scheme_data(post, options)
        post['payment_method_options'] = { 'card' => { 'risk_control' => { 'three_ds_action' => 'SKIP_3DS' } } } if options[:skip_3ds]

        commit(:setup, post)
      end

      def add_billing(post, card, options = {})
        billing_address = options[:billing_address] || {}
        first_name, last_name = billing_names(card, billing_address)
        # Airwallex requires both names whenever billing data is sent.
        return unless first_name.present? && last_name.present?

        billing = post['payment_method']['card']['billing'] || {}
        email = options[:email] || billing_address[:email]
        phone = options[:phone] || billing_address[:phone]
        billing['email'] = email if email.present?
        billing['phone'] = phone if phone.present?
        billing['first_name'] = first_name
        billing['last_name'] = last_name
        billing['address'] = build_address(billing_address) if has_required_address_info?(billing_address)

        post['payment_method']['card']['billing'] = billing
      end

      # Falls back to the billing address name when the card carries no cardholder name.
      def billing_names(card, billing_address)
        return [card.first_name, card.last_name] if card.first_name.present? && card.last_name.present?

        split_names(billing_address[:name])
      end

      def has_required_address_info?(address)
        # These fields are required if address data is sent.
        return unless address

        address[:address1] && address[:country]
      end

      def build_address(address)
        return unless address

        address_data = {} # names r hard
        address_data[:country_code] = address[:country]
        address_data[:street] = address[:address1]
        address_data[:city] = address[:city] if address[:city] # required per doc, not in practice
        address_data[:postcode] = address[:zip] if address[:zip]
        address_data[:state] = address[:state] if address[:state]
        address_data
      end

      def add_invoice(post, money, options)
        currency = options[:currency] || currency(money)
        post[:amount] = localized_amount(money, currency)
        post[:currency] = currency
      end

      def add_card(post, card, options = {})
        post['payment_method'] = {
          'type' => 'card',
          'card' => {
            'expiry_month' => format(card.month, :two_digits),
            'expiry_year' => card.year.to_s,
            'number' => card.number.to_s,
            'name' => card.name,
            'brand' => card.brand
          }
        }
        # Send no cvc key at all when there is none, rather than "cvc": null.
        post['payment_method']['card']['cvc'] = card.verification_value if card.verification_value.present?
        add_billing(post, card, options)
      end

      def add_order(post, options)
        return unless options[:shipping_address] || options[:products]

        if shipping_address = options[:shipping_address]
          physical_address = build_shipping_address(shipping_address)
          first_name, last_name = split_names(shipping_address[:name])
          shipping = {}
          shipping[:first_name] = first_name if first_name
          shipping[:last_name] = last_name if last_name
          # Callers send the ActiveMerchant :phone key; :phone_number is kept for existing integrations.
          phone_number = shipping_address[:phone_number] || shipping_address[:phone]
          shipping[:phone_number] = phone_number if phone_number.present?
          shipping[:address] = physical_address
        end

        order = {}
        order[:shipping] = shipping if shipping
        order[:products] = options[:products] if options[:products]

        post[:order] = order
      end

      def build_shipping_address(shipping_address)
        address = {}
        address[:city] = shipping_address[:city]
        address[:country_code] = shipping_address[:country]
        address[:postcode] = shipping_address[:zip]
        address[:state] = shipping_address[:state]
        address[:street] = shipping_address[:address1]
        address
      end

      # Level 2/Level 3 data forwarded to the card schemes, which may qualify the
      # transaction for reduced interchange. Accepted on payment intent creation only.
      def add_enhanced_scheme_data(post, options)
        return unless scheme_data = options[:enhanced_scheme_data]

        scheme_data = scheme_data.transform_keys(&:to_sym)
        data = {}

        ENHANCED_SCHEME_DATA_LIMITS.each { |field, limit| data[field] = truncate(scheme_data[field], limit) if scheme_data[field] }
        ENHANCED_SCHEME_DATA_AMOUNTS.each { |field| data[field] = scheme_data_amount(scheme_data[field]) if scheme_data[field] }
        data[:summary_commodity_code] = scheme_data[:summary_commodity_code] if scheme_data[:summary_commodity_code]

        data[:customer] = build_scheme_data_customer(scheme_data[:customer]) if scheme_data[:customer]
        data[:shipping] = build_scheme_data_shipping(scheme_data[:shipping]) if scheme_data[:shipping]
        data[:products] = scheme_data[:products].map { |product| build_scheme_data_product(product) } if scheme_data[:products].present?

        return if data.empty?

        post[:additional_info] = { enhanced_scheme_data: data }
      end

      def build_scheme_data_customer(customer)
        customer = customer.transform_keys(&:to_sym)

        data = {}
        data[:first_name] = customer[:first_name] if customer[:first_name]
        data[:last_name] = customer[:last_name] if customer[:last_name]
        data[:reference] = truncate(customer[:reference], 17) if customer[:reference]
        data
      end

      def build_scheme_data_shipping(shipping)
        shipping = shipping.transform_keys(&:to_sym)

        data = {}
        data[:date] = shipping[:date] if shipping[:date]
        data[:fee_amount] = scheme_data_amount(shipping[:fee_amount]) if shipping[:fee_amount]
        data[:from_postcode] = truncate(shipping[:from_postcode], 10) if shipping[:from_postcode]
        data[:address] = build_scheme_data_address(shipping[:address]) if shipping[:address]
        data
      end

      # Accepts either Airwallex field names or the ActiveMerchant address keys.
      def build_scheme_data_address(address)
        address = address.transform_keys(&:to_sym)

        data = {}
        data[:country_code] = address[:country_code] || address[:country]
        data[:street] = truncate(address[:street] || address[:address1], ENHANCED_SCHEME_DATA_ADDRESS_LIMITS[:street])
        data[:city] = truncate(address[:city], ENHANCED_SCHEME_DATA_ADDRESS_LIMITS[:city])
        data[:postcode] = truncate(address[:postcode] || address[:zip], ENHANCED_SCHEME_DATA_ADDRESS_LIMITS[:postcode])
        data[:state] = truncate(address[:state], ENHANCED_SCHEME_DATA_ADDRESS_LIMITS[:state])
        data.compact
      end

      def build_scheme_data_product(product)
        product = product.transform_keys(&:to_sym)

        data = {}
        ENHANCED_SCHEME_DATA_PRODUCT_LIMITS.each { |field, limit| data[field] = truncate(product[field], limit) if product[field] }
        ENHANCED_SCHEME_DATA_PRODUCT_AMOUNTS.each { |field| data[field] = scheme_data_amount(product[field]) if product[field] }
        data[:quantity] = product[:quantity] if product[:quantity]
        data[:tax_percent] = product[:tax_percent] if product[:tax_percent]
        data
      end

      # Enhanced scheme data amounts are expressed in the original currency of the
      # transaction rather than in minor units. Integers are converted per the
      # ActiveMerchant convention that money is passed in cents; values already
      # given as decimals are sent through untouched.
      def scheme_data_amount(value)
        value.is_a?(Integer) ? amount(value).to_f : value
      end

      def add_stored_credential(post, options)
        return unless stored_credential = options[:stored_credential]

        external_recurring_data = post[:external_recurring_data] = {}

        case stored_credential.dig(:reason_type)
        when 'recurring', 'installment'
          external_recurring_data[:merchant_trigger_reason] = 'scheduled'
        when 'unscheduled'
          external_recurring_data[:merchant_trigger_reason] = 'unscheduled'
        end

        original_transaction_id = test_network_transaction_id(post) if test_mit?(options)
        original_transaction_id ||= stored_credential.dig(:network_transaction_id)
        external_recurring_data[:original_transaction_id] = original_transaction_id if original_transaction_id.present?
        external_recurring_data[:triggered_by] = stored_credential.dig(:initiator) == 'cardholder' ? 'customer' : 'merchant'
      end

      def test_network_transaction_id(post)
        case post['payment_method']['card']['brand']
        when 'visa'
          TEST_NETWORK_TRANSACTION_IDS[:visa]
        when 'master'
          TEST_NETWORK_TRANSACTION_IDS[:master]
        end
      end

      def test_mit?(options)
        test? && options.dig(:stored_credential, :initiator) == 'merchant'
      end

      def add_three_ds(post, options)
        return unless three_d_secure = options[:three_d_secure]

        pm_options = post.dig('payment_method_options', 'card')

        external_three_ds = {
          version: format_three_ds_version(three_d_secure),
          eci: three_d_secure[:eci]
        }.merge(three_ds_version_specific_fields(three_d_secure))

        pm_options ? pm_options.merge!(external_three_ds:) : post['payment_method_options'] = { card: { external_three_ds: } }
      end

      def format_three_ds_version(three_d_secure)
        version = three_d_secure[:version].split('.')

        version.push('0') until version.length == 3
        version.join('.')
      end

      def three_ds_version_specific_fields(three_d_secure)
        if three_d_secure[:version].to_f >= 2
          {
            authentication_value: three_d_secure[:cavv],
            ds_transaction_id: three_d_secure[:ds_transaction_id],
            three_ds_server_transaction_id: three_d_secure[:three_ds_server_trans_id]
          }
        else
          {
            cavv: three_d_secure[:cavv],
            xid: three_d_secure[:xid]
          }
        end
      end

      def authorization_only?(options = {})
        options.include?(:auto_capture) && options[:auto_capture] == false
      end

      def add_descriptor(post, options)
        post[:descriptor] = truncate(options[:description], 32) if options[:description]
      end

      def parse(body)
        JSON.parse(body)
      end

      def commit(action, post, id = nil)
        url = build_request_url(action, id)

        post_headers = { 'Authorization' => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
        response = parse(ssl_post(url, post_data(post), post_headers))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response.dig('latest_payment_attempt', 'authentication_data', 'avs_result')),
          cvv_result: CVVResult.new(response.dig('latest_payment_attempt', 'authentication_data', 'cvc_code')),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def handle_response(response)
        case response.code.to_i
        when 200...300, 400, 404
          response.body
        else
          raise ResponseError.new(response)
        end
      end

      def post_data(post)
        post.to_json
      end

      def success_from(response)
        %w(REQUIRES_PAYMENT_METHOD SUCCEEDED RECEIVED REQUIRES_CAPTURE CANCELLED).include?(response['status'])
      end

      def message_from(response)
        response.dig('latest_payment_attempt', 'status') || response['status'] || issuer_decline_message(response) || response['message']
      end

      def issuer_decline_message(response)
        return unless response['code'] == 'issuer_declined'

        ISSUER_DECLINE_MESSAGES[response['provider_original_response_code']]
      end

      def authorization_from(response)
        response.dig('latest_payment_attempt', 'payment_intent_id') || response.dig('payment_intent_id')
      end

      def error_code_from(response)
        response['provider_original_response_code'] || response['code'] unless success_from(response)
      end
    end
  end
end
