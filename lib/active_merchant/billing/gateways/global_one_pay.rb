module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GlobalOnePayGateway < Gateway
      self.test_url = 'https://testpayments.globalone.me/merchant/xmlpayment'
      self.live_url = 'https://payments.globalone.me/merchant/xmlpayment'

      ACTIONS = {
        authorize: 'PREAUTH',
        purchase: 'PAYMENT',
        capture: 'PREAUTHCOMPLETION',
        refund: 'REFUND',
        open_refund: 'UNREFERENCEDREFUND'
      }

      BRANDS = {
        visa: 'VISA',
        master: 'MASTERCARD',
        american_express: 'AMEX',
        jcb: 'JCB',
        discover: 'DISCOVER',
        diners_club: 'DINERS',
        maestro: 'MAESTRO',
        laser: 'LASER',
        electron: 'ELECTRON'
      }

      POST_HEADERS = {
        'Accepts' => 'application/xml',
        'Content-Type' => 'application/xml'
      }

      self.default_currency = 'USD'
      self.money_format = :dollars
      self.supported_countries = %w[IE GB US]
      self.supported_cardtypes = %i[visa master american_express jcb discover diners_club maestro]
      self.homepage_url = 'http://www.globalonepay.com'
      self.display_name = 'Global One Pay'

      def initialize(options = {})
        requires!(options, :tid, :private_key)
        super
      end

      def authorize(amount, credit_card, options = {})
        requires!(options, :order_id, :currency)
        commit(:authorize, build_sale_or_authorization_request(amount, credit_card, options))
      end

      def purchase(amount, credit_card, options = {})
        requires!(options, :order_id, :currency)
        commit(:purchase, build_sale_or_authorization_request(amount, credit_card, options))
      end

      def capture(amount, authorization, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        commit(:capture, build_capture_or_refund_request(:capture, amount, authorization, options))
      end

      def refund(amount, authorization, options = {})
        if options.include?(:credit_card)
          requires!(options, :operator_id, :order_id, :currency)
          credit_card = options[:credit_card]
          commit(:open_refund, build_open_credit_request(amount, credit_card, options))
        else
          requires!(options, :operator_id, :reverse_reason)
          raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

          commit(:refund, build_capture_or_refund_request(:refund, amount, authorization, options))
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r{(<CARDNUMBER>)[^<]*(<\/CARDNUMBER>)}, '\1[FILTERED]\2').
          gsub(%r{(<CVV>)[^<]*(<\/CVV>)}, '\1[FILTERED]\2')
      end

      private

      def build_request(action, body)
        xml = Builder::XmlMarkup.new

        xml.instruct!
        xml.tag! ACTIONS[action] do
          xml << body
        end

        xml.target!
      end

      def build_sale_or_authorization_request(amount, credit_card, options)
        xml = Builder::XmlMarkup.new

        xml.tag! 'ORDERID', options[:order_id]
        xml.tag! 'TERMINALID', @options[:tid]
        localized = add_amount(xml, amount, options)
        datetime = add_datetime(xml)
        add_credit_card(xml, credit_card, options)
        add_auth_purchase_hash(xml, localized, datetime, options)
        xml.tag! 'CURRENCY', options[:currency]
        xml.tag! 'TERMINALTYPE', options[:terminal_type] || '2'
        xml.tag! 'TRANSACTIONTYPE', options[:moto_ecommerce_ind] || '7'
        xml.tag! 'EMAIL', options[:email] if options[:email].present?
        xml.tag! 'CVV', credit_card.verification_value if credit_card.verification_value?
        add_address(xml, options)
        xml.tag! 'DESCRIPTION', options[:description] if options[:description].present?
        add_more_address(xml, options)
        xml.tag! 'IPADDRESS', options[:ip] if options[:ip].present?

        xml.target!
      end

      def build_capture_or_refund_request(action, amount, identification, options)
        xml = Builder::XmlMarkup.new

        xml.tag! 'UNIQUEREF', identification
        xml.tag! 'TERMINALID', @options[:tid]
        localized = add_amount(xml, amount, options)
        xml.tag! 'DESCRIPTION', options[:description] if options[:description].present? && action == :capture
        datetime = add_datetime(xml)
        add_capture_hash(xml, localized, datetime, identification)
        if action == :refund
          xml.tag! 'OPERATOR', options[:operator_id]
          xml.tag! 'REASON', options[:reverse_reason]
        end

        xml.target!
      end

      def build_open_credit_request(amount, credit_card, options)
        xml = Builder::XmlMarkup.new

        xml.tag! 'ORDERID', options[:order_id]
        xml.tag! 'TERMINALID', @options[:tid]
        xml.tag! 'CARDDETAILS' do
          xml.tag! 'CARDTYPE', card_type(credit_card)
          xml.tag! 'CARDNUMBER', credit_card.number
          xml.tag! 'CARDEXPIRY', expdate(credit_card)
          xml.tag! 'CARDHOLDERNAME', credit_card.name
        end
        xml.tag! 'CURRENCY', options[:currency]
        localized = add_amount(xml, amount, options)
        xml.tag! 'EMAIL', options[:email] if options[:email].present?
        datetime = add_datetime(xml)
        add_open_credit_purchase_hash(xml, localized, datetime, credit_card, options)
        xml.tag! 'OPERATOR', options[:operator_id]
        xml.tag! 'DESCRIPTION', options[:description] if options[:description].present?

        xml.target!
      end

      def add_auth_purchase_hash(xml, localized, datetime, options)
        if @options[:region] && @options[:region].to_s.upcase == 'MCP'
          xml.tag! 'HASH', Digest::MD5.hexdigest("#{@options[:tid]}#{options[:order_id]}#{options[:currency]}#{localized}#{datetime}#{@options[:private_key]}")
        else
          xml.tag! 'HASH', Digest::MD5.hexdigest("#{@options[:tid]}#{options[:order_id]}#{localized}#{datetime}#{@options[:private_key]}")
        end
      end

      def add_capture_hash(xml, localized, datetime, auth)
        xml.tag! 'HASH', Digest::MD5.hexdigest("#{@options[:tid]}#{auth}#{localized}#{datetime}#{@options[:private_key]}")
      end

      def add_open_credit_purchase_hash(xml, localized, datetime, credit_card, options)
        if @options[:region] && @options[:region].to_s.upcase == 'MCP'
          xml.tag! 'HASH', Digest::MD5.hexdigest("#{@options[:tid]}#{options[:order_id]}#{card_type(credit_card)}#{credit_card.number}#{expdate(credit_card)}#{credit_card.name}#{options[:currency]}#{localized}#{datetime}#{@options[:private_key]}")
        else
          xml.tag! 'HASH', Digest::MD5.hexdigest("#{@options[:tid]}#{options[:order_id]}#{card_type(credit_card)}#{credit_card.number}#{expdate(credit_card)}#{credit_card.name}#{localized}#{datetime}#{@options[:private_key]}")
        end
      end

      def add_datetime(xml)
        datetime = Time.now.gmtime.strftime('%d-%m-%Y:%H:%M:%S:%L')
        xml.tag! 'DATETIME', datetime
        datetime
      end

      def add_amount(xml, amount, options)
        localized = localized_amount(amount, options[:currency])
        xml.tag! 'AMOUNT', localized
        localized
      end

      def add_credit_card(xml, credit_card, options)
        xml.tag! 'CARDNUMBER', credit_card.number
        xml.tag! 'CARDTYPE', card_type(credit_card)
        xml.tag! 'CARDEXPIRY', expdate(credit_card)
        xml.tag! 'CARDHOLDERNAME', credit_card.name
      end

      def card_type(credit_card)
        card_type = card_brand(credit_card).to_sym

        if card_type == :visa && credit_card.respond_to?(:electron?) && credit_card.electron?
          BRANDS[:electron]
        else
          BRANDS[card_type]
        end
      end

      def add_address(xml, options)
        if address = (options[:billing_address] || options[:address])
          xml.tag! 'ADDRESS1', address[:address1] if address[:address1].present?
          xml.tag! 'ADDRESS2', address[:address2] if address[:address2].present?
          xml.tag! 'POSTCODE', address[:zip] if address[:zip].present?
        end
      end

      def add_more_address(xml, options)
        if address = (options[:billing_address] || options[:address])
          xml.tag! 'CITY', address[:city] if address[:city].present?
          xml.tag! 'REGION', address[:state] if address[:state].present?
          xml.tag! 'COUNTRY', address[:country] if address[:country].present?
        end
      end

      def commit(action, request, credit_card = nil)
        url = (test? ? self.test_url : self.live_url)
        response = parse(action, ssl_post(url, build_request(action, request), POST_HEADERS))

        Response.new(successful?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response),
          avs_result: { code: response[:avsresponse] },
          cvv_result: response[:cvvresponse]
        )
      end

      def successful?(response)
        return false if response[:errorstring].present?

        response[:responsecode] == 'A'
      end

      def authorization_from(response)
        response[:uniqueref]
      end

      def message_from(response)
        return response[:errorstring] if response[:errorstring].present?

        response[:responsetext]
      end

      def parse(action, body)
        response = {}
        xml = REXML::Document.new(body)
        root = REXML::XPath.first(xml, "//#{ACTIONS[action]}RESPONSE") ||
               REXML::XPath.first(xml, '//ERROR')
        if root
          root.elements.to_a.each do |node|
            recurring_parse_element(response, node)
          end
        end
        response
      end

      def recurring_parse_element(response, node)
        if node.has_elements?
          node.elements.each { |e| recurring_parse_element(response, e) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end
    end
  end
end
