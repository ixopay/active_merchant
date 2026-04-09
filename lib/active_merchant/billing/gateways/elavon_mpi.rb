module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class ElavonMpiGateway < Gateway
      class XmlConnection < ActiveMerchant::Connection
        def request(method, body, headers = {})
          super(method, body, { 'Accept' => 'application/xml', 'Content-Type' => 'application/xml' })
        end
      end

      self.default_currency = 'USD'
      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master]
      self.homepage_url = 'http://www.elavon.com/'
      self.display_name = 'Elavon'

      self.test_url = 'https://testempi.internetsecure.com/IS3DSecureMPI/request/merchant'
      self.live_url = 'https://empi.internetsecure.com/IS3DSecureMPI/request/merchant'

      def initialize(options = {})
        requires!(options, :merchant_id, :application_key)
        super
      end

      def authorize(money, credit_card, options = {})
        post = {
          version: '1.0.0',
          merchantId: @options[:merchant_id],
          applicationKey: @options[:application_key],
          verifyEnrollmentRequest: {
            accountData: add_payment(credit_card),
            browser: add_browser,
            purchaseDate: Time.now,
            purchaseAmount: money,
            purchaseCurrency: 840,
            orderDescription: options[:order_description] || ''
          }
        }

        commit('lookup', post)
      end

      def capture(money, authorization, options = {})
        pa_res, transaction_id = authorization.split(';')

        post = {
          version: '1.0.0',
          merchantId: @options[:merchant_id],
          applicationKey: @options[:application_key],
          xid: transaction_id,
          validateParesRequest: {
            paRes: pa_res
          }
        }

        commit('verify', post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((<accountId>)[^<]*(</accountId>)), '\1[FILTERED]\2').
          gsub(%r((<applicationKey>)[^<]*(</applicationKey>)), '\1[FILTERED]\2')
      end

      private

      def add_payment(credit_card)
        {
          accountId: credit_card.number,
          expiryYear: format(credit_card.year, :four_digits),
          expiryMonth: format(credit_card.month, :two_digits)
        }
      end

      def add_browser
        {
          deviceCategory: 0,
          accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          userAgent: 'Ruby AM 1.0'
        }
      end

      def parse(body)
        Hash.from_xml(body).fetch('response')
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(parameters)))
        payload_key = key_for_action(action)

        Response.new(
          success_from(response[payload_key]),
          message_from(response[payload_key]),
          response,
          test: test?
        )
      end

      def success_from(response)
        response['enrolled'] == 'Y' ||
          response['status'] == 'Y'
      end

      def message_from(response)
        ''
      end

      def key_for_action(action)
        if action == 'lookup'
          'verifyEnrollmentResponse'
        else
          'validateParesResponse'
        end
      end

      def post_data(parameters = {})
        xml = REXML::Document.new
        root = xml.add_element('request')
        root.add_attribute("id", SecureRandom.hex(10))

        parameters.each do |key, value|
          if value.is_a?(Hash)
            child = root.add_element(key.to_s)
            extract_from_hash(value, child)
          else
            root.add_element(key.to_s).text = value
          end
        end

        root.to_s
      end

      def extract_from_hash(hsh, xml_node)
        hsh.each do |key, value|
          if value.is_a?(Hash)
            child = xml_node.add_element(key.to_s)
            extract_from_hash(value, child)
          else
            xml_node.add_element(key.to_s).text = value
          end
        end
      end

      def new_connection(endpoint)
        XmlConnection.new(endpoint)
      end
    end
  end
end
