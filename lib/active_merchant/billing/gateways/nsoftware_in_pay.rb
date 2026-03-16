require 'json'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class NsoftwareInPayGateway < Gateway
      class JSONConnection < ActiveMerchant::Connection
        def request(method, body, headers = {})
          super(method, body, { 'Accept' => 'application/json', 'Content-Type' => 'application/json' })
        end
      end

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://www.nsoftware.com/'
      self.display_name = 'nSoftware'

      self.test_url = 'https://mpi.paay.co/'
      self.live_url = 'https://mpi.paay.co/'

      def initialize(options = {})
        super
      end

      def authorize(money, credit_card, options = {})
        requires!(options, :transaction_id, :message_id, :return_url)

        post = {
          action: 'auth-request',
          data: {
            amount: money,
            transaction_id: options[:transaction_id],
            message_id: options[:message_id],
            return_url: options[:return_url]
          }
        }
        add_payment(post, credit_card)

        commit('authorize', post)
      end

      def capture(money, authorization, options = {})
        raise ArgumentError, 'Missing required parameter: credit_card' unless options.include?(:credit_card)
        creditcard = options[:credit_card]

        pa_res, transaction_id = authorization.to_s.split(';')

        post = {
          action: 'auth-response',
          data: {
            pares: pa_res,
            amount: money,
            transaction_id: transaction_id,
            message_id: options[:message_id],
          }
        }
        add_payment(post, creditcard)

        commit('capture', post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r("token"\s*:\s*"[^"]*")i, '"token":"[FILTERED]"').
          gsub(%r("card_exp_month"\s*:\s*"[^"]*")i, '"card_exp_month":"[FILTERED]"').
          gsub(%r("card_exp_year"\s*:\s*"[^"]*")i, '"card_exp_year":"[FILTERED]"')
      end

      private

      def add_payment(post, credit_card)
        raise ArgumentError, 'Missing required parameter: credit_card:number' if credit_card.number.blank?
        raise ArgumentError, 'Missing required parameter: credit_card:month' if credit_card.month.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:year' if credit_card.year.nil?
        post[:data][:token] = credit_card.number
        post[:data][:card_exp_month] = format(credit_card.month, :two_digits)
        post[:data][:card_exp_year] = format(credit_card.year, :four_digits)
      end

      def parse(body)
        JSON.parse(body)
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(action, parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          test: test?
        )
      end

      def success_from(response)
        response['success'] == 'true' ||
          (response['AcsUrl'].present? && response['PaReq'].present?)
      end

      def message_from(response)
        response['error']
      end

      def post_data(action, parameters = {})
        JSON.generate(parameters)
      end

      def new_connection(endpoint)
        JSONConnection.new(endpoint)
      end
    end
  end
end
