require 'securerandom'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BraspagGateway < Gateway
      self.display_name = 'Braspag'
      self.homepage_url = 'https://www.braspag.com.br/'
      self.supported_countries = ['BR']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :elo]
      self.default_currency = 'BRL'
      self.money_format = :cents

      self.test_url = 'https://apisandbox.braspag.com.br/v2/sales/'
      self.live_url = 'https://api.braspag.com.br/v2/sales/'

      def initialize(options = {})
        requires!(options, :merchant_id, :private_key, :network)
        super
      end

      def authorize(amount, payment_method, options = {})
        post = {}
        post[:MerchantOrderId] = options[:order_id]

        add_customer(post, payment_method, options)
        add_payment(post, amount, payment_method, options, :authorize)

        commit(:authorize, post)
      end

      def purchase(amount, payment_method, options = {})
        post = {}
        post[:MerchantOrderId] = options[:order_id]

        add_customer(post, payment_method, options)
        add_payment(post, amount, payment_method, options, :purchase)

        commit(:purchase, post)
      end

      def capture(amount, authorization, options = {})
        @capture_suffix = "#{authorization}/capture?amount=#{amount}&serviceTaxAmount=#{options[:tax]}"

        commit(:capture, nil)
      end

      def void(authorization, options = {})
        @void_suffix = "#{authorization}/void"

        commit(:void, nil)
      end

      def refund(amount, authorization, options = {})
        @refund_suffix = "#{authorization}/void?amount=#{amount}"

        commit(:refund, nil)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((\"CardNumber\":\s*\")[^\"]*), '\1[FILTERED]').
          gsub(%r((\"SecurityCode\":\s*\")[^\"]*), '\1[FILTERED]').
          gsub(%r((MerchantKey:\s*)[^\s]+), '\1[FILTERED]')
      end

      private

      def add_customer(post, card_options, options)
        post[:Customer] = {
          Name: card_options.name.to_s
        }
        post[:Customer][:Identity] = options[:user_data_1] if options[:user_data_1]
        post[:Customer][:IdentityType] = 'CPF' if options[:user_data_1]
        post[:Customer][:Email] = options[:email] if options[:email]

        if (billing_address = options[:billing_address])
          post[:Customer][:Address] = {}
          post[:Customer][:Address][:Street] = billing_address[:address1] if billing_address[:address1]
          post[:Customer][:Address][:Number] = billing_address[:address2] if billing_address[:address2]
          post[:Customer][:Address][:ZipCode] = billing_address[:zip] if billing_address[:zip]
          post[:Customer][:Address][:City] = billing_address[:city] if billing_address[:city]
          post[:Customer][:Address][:State] = billing_address[:state] if billing_address[:state]
          post[:Customer][:Address][:Country] = billing_address[:country] if billing_address[:country]
        end

        if (shipping_address = options[:shipping_address])
          post[:Customer][:DeliveryAddress] = {}
          post[:Customer][:DeliveryAddress][:Street] = shipping_address[:address1] if shipping_address[:address1]
          post[:Customer][:DeliveryAddress][:Number] = shipping_address[:address2] if shipping_address[:address2]
          post[:Customer][:DeliveryAddress][:ZipCode] = shipping_address[:zip] if shipping_address[:zip]
          post[:Customer][:DeliveryAddress][:City] = shipping_address[:city] if shipping_address[:city]
          post[:Customer][:DeliveryAddress][:State] = shipping_address[:state] if shipping_address[:state]
          post[:Customer][:DeliveryAddress][:Country] = shipping_address[:country] if shipping_address[:country]
        end
      end

      def add_payment(post, amount, payment_options, transaction_options, action)
        post[:Payment] = {
          Provider: @options[:network].nil? ? 'Simulado' : @options[:network],
          Type: 'CreditCard',
          Amount: amount,
          ServiceTaxAmount: transaction_options[:tax] ? 0 : transaction_options[:tax],
          Capture: action == :purchase,
          Installments: transaction_options[:recurring_ind].nil? ? 1 : transaction_options[:recurring_ind],
          CreditCard: {
            CardNumber: payment_options.number,
            Holder: payment_options.name.to_s,
            ExpirationDate: "#{payment_options.month.to_s.rjust(2, '0')}/#{payment_options.year}",
            SecurityCode: payment_options.verification_value,
            Brand: payment_options.brand
          }
        }
        post[:Payment][:Currency] = transaction_options[:currency] if transaction_options[:currency]
        post[:Payment][:Country] = transaction_options[:payment_country] if transaction_options[:payment_country]

        if @options[:avs_enabled] && transaction_options[:user_data_1]
          post[:Payment][:Avs] = {
            Cpf: transaction_options[:user_data_1]
          }

          if (billing_address = transaction_options[:billing_address])
            post[:Payment][:Avs][:ZipCode] = billing_address[:zip] if billing_address[:zip]
            post[:Payment][:Avs][:Street] = billing_address[:address1] if billing_address[:address1]
            post[:Payment][:Avs][:Number] = billing_address[:address2] if billing_address[:address2]
          end
        end
      end

      def commit(action, post)
        raw_response = ssl_request(http_method(action), url(action), post.nil? ? nil : post.to_json, headers)
        response = parse(raw_response)

        succeeded = success_from(action, response)

        Response.new(
          succeeded,
          message_from(succeeded, action, response),
          response,
          authorization: authorization_from(response),
          test: test?
        )
      rescue ResponseError => e
        raise unless e.response.code =~ /4\d\d/

        response = parse(e.response.body)[0]
        return Response.new(
          false,
          "#{response['Code']}: #{response['Message']}",
          response,
          test: test?
        )
      rescue JSON::ParserError
        unparsable_response(raw_response)
      end

      def unparsable_response(raw_response)
        message = "Unparsable response received from Braspag. Please contact Braspag if you continue to receive this message."
        message += " (The raw response returned by the API was #{raw_response.inspect})"
        return Response.new(false, message)
      end

      def headers
        {
          'Content-Type' => 'application/json',
          'MerchantId' => @options[:merchant_id],
          'MerchantKey' => @options[:private_key],
          'RequestId' => SecureRandom.uuid
        }
      end

      def url(action)
        case action
        when :authorize, :purchase
          test? ? test_url : live_url
        when :capture
          (test? ? test_url : live_url) + @capture_suffix
        when :void
          (test? ? test_url : live_url) + @void_suffix
        when :refund
          (test? ? test_url : live_url) + @refund_suffix
        end
      end

      def http_method(action)
        case action
        when :authorize, :purchase
          :post
        when :capture, :void, :refund
          :put
        end
      end

      def parse(body)
        JSON.parse(body)
      end

      def success_from(action, response)
        case action
        when :authorize, :purchase
          response.key?('Payment') && response['Payment'].key?('ReasonCode') && response['Payment']['ReasonCode'] == 0
        when :capture, :void, :refund
          response.key?('ReasonCode') && response['ReasonCode'] == 0
        end
      rescue
        false
      end

      def message_from(succeeded, action, response)
        if succeeded
          return "Succeeded"
        else
          case action
          when :authorize, :purchase
            response.key?('Payment') && response['Payment'].key?('ReasonMessage') ? response['Payment']['ReasonMessage'] : response.to_s
          when :capture, :void, :refund
            response.key?('ReasonMessage') ? response['ReasonMessage'] : response.to_s
          end
        end
      rescue
        response.to_s
      end

      def authorization_from(response)
        response.key?('Payment') && response['Payment'].key?('PaymentId') ? response['Payment']['PaymentId'] : 0
      rescue
        0
      end
    end
  end
end
