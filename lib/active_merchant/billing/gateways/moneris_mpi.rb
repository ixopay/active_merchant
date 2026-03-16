module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MonerisMpiGateway < Gateway
      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://www.moneris.com/'
      self.display_name = 'Moneris'

      self.test_url = 'https://esplusqa.moneris.com/mpi/servlet/MpiServlet'
      self.live_url = 'https://esplus.moneris.com/mpi/servlet/MpiServlet'

      def initialize(options = {})
        requires!(options, :store_id, :api_token)
        super
      end

      def authorize(money, credit_card, options = {})
        requires!(options, :transaction_id)
        post = @options.dup
        post[:txn] = {
          xid: options[:transaction_id],
          amount: money.to_s.insert(-3, '.'),
          MD: options[:transaction_id],
          merchantUrl: 'https://acs-callback.herokuapp.com/acs_callback',
          accept: '*/*',
          userAgent: 'Ruby AM v1.0'
        }
        add_payment(post, credit_card)

        commit('MpiRequest', post)
      end

      def capture(money, authorization, options = {})
        pa_res, transaction_id = authorization.to_s.split(';')

        post = @options.dup
        post[:acs] = { PaRes: pa_res, MD: transaction_id }

        commit('MpiRequest', post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(<pan>[^<]*</pan>)i, '<pan>[FILTERED]</pan>').
          gsub(%r(<api_token>[^<]*</api_token>)i, '<api_token>[FILTERED]</api_token>')
      end

      private

      def add_payment(post, credit_card)
        post[:txn][:pan] = credit_card.number
        post[:txn][:expdate] = "#{format(credit_card.year, :two_digits)}#{format(credit_card.month, :two_digits)}"
      end

      def parse(body)
        Hash.from_xml(body).fetch('MpiResponse')
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
        response['success'] == 'true'
      end

      def message_from(response)
        response['message']
      end

      def post_data(action, parameters = {})
        xml = REXML::Document.new
        root = xml.add_element(action)

        parameters.each do |key, value|
          if value.is_a?(Hash)
            child = root.add_element(key.to_s)
            value.each do |txn_key, txn_value|
              child.add_element(txn_key.to_s).text = txn_value
            end
          else
            root.add_element(key.to_s).text = value
          end
        end

        root.to_s
      end
    end
  end
end
