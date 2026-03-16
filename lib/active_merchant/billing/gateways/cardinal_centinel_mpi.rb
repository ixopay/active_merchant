module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CardinalCentinelMpiGateway < Gateway
      self.supported_countries = ['US', 'GR']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express]
      self.ssl_strict = true

      self.homepage_url = 'http://www.cardinalcommerce.com'
      self.display_name = 'Centinel 3D Secure'

      self.test_url = 'https://centineltest.cardinalcommerce.com/maps/txns.asp'
      self.live_url = 'https://centinel1000.cardinalcommerce.com/maps/txns.asp'

      def initialize(options = {})
        requires!(options, :processor_id, :merchant_id, :password)
        super
      end

      def authorize(money, credit_card, options = {})
        requires!(options, :currency_code, :order_number)
        post = {
          MsgType: 'cmpi_lookup',
          Version: 1.7,
          TransactionType: 'C',
          CurrencyCode: options[:currency_code],
          OrderNumber: options[:order_number],
          Amount: money,
          ProcessorId: @options[:processor_id],
          MerchantId: @options[:merchant_id],
          TransactionPwd: @options[:password]
        }
        add_payment(post, credit_card)

        commit('lookup', post)
      end

      def capture(money, authorization, options = {})
        pa_res, transaction_id = authorization.to_s.split(';')

        post = {
          MsgType: 'cmpi_authenticate',
          Version: 1.7,
          TransactionType: 'C',
          TransactionId: transaction_id,
          PAResPayload: pa_res,
          TransactionUrl: test? ? test_url : live_url,
          ProcessorId: @options[:processor_id],
          MerchantId: @options[:merchant_id],
          TransactionPwd: @options[:password]
        }

        commit('authenticate', post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((<CardNumber>)[^<]*(</CardNumber>)), '\1[FILTERED]\2').
          gsub(%r((<TransactionPwd>)[^<]*(</TransactionPwd>)), '\1[FILTERED]\2')
      end

      private

      def add_payment(post, credit_card)
        post[:CardNumber] = credit_card.number
        post[:CardExpYear] = credit_card.year
        post[:CardExpMonth] = format(credit_card.month, :two_digits)
      end

      def parse(body)
        Hash.from_xml(body).fetch('CardinalMPI')
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

      def post_data(action, parameters = {})
        xml = REXML::Document.new
        root = xml.add_element('CardinalMPI')

        parameters.each do |key, value|
          root.add_element(key.to_s).text = value
        end

        "cmpi_msg=#{CGI.escape(root.to_s)}"
      end

      def success_from(response)
        response.fetch('ErrorDesc').nil? &&
          response.fetch('ErrorNo') == '0'
      end

      def message_from(response)
        response['ErrorDesc'] || ''
      end
    end
  end
end
