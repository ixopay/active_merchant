module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # First Data Compass Platform using the Online XML Specification
    class FirstdataCompassGateway < Gateway
      self.live_url = 'https://ws.firstdatacompass.com/cmpwsapi/services/order.wsdl'
      self.test_url = 'https://merchanttest.ctexmloma.compass-xml.com/cmpwsapi/services/order.wsdl'

      self.supported_countries = ['US', 'CA']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :jcb]
      self.default_currency = '840'
      self.money_format = :cents
      self.homepage_url = 'http://www.firstdata.com'
      self.display_name = 'FirstData Compass Platform'

      ENVELOPE_NAMESPACES = {
        'xmlns:soapenv' => 'http://schemas.xmlsoap.org/soap/envelope/',
        'xmlns:cmp' => 'http://firstdata.com/cmpwsapi/schemas/cmpapi'
      }.freeze

      REQUEST_NAMESPACES = {
        'xmlns:cmpapi' => 'http://firstdata.com/cmpwsapi/schemas/cmpapi',
        'xmlns:cmpmsg' => 'http://firstdata.com/cmpwsapi/schemas/cmpmsg'
      }.freeze

      FRAUD_CODE = '200'
      SENSITIVE_FIELDS = [:AccountNumber].freeze

      AVS_CODE_TRANSLATOR = {
        'IG' => 'E', 'IU' => 'E', 'ID' => 'S', 'IE' => 'E',
        'IS' => 'R', 'IA' => 'D', 'IB' => 'B', 'IC' => 'C',
        'IP' => 'P', 'A3' => 'V', 'B3' => 'H', 'B4' => 'F',
        'B7' => 'T', '??' => 'R', 'I1' => 'M', 'I2' => 'W',
        'I3' => 'Y', 'I4' => 'Z', 'I5' => 'X', 'I6' => 'W',
        'I7' => 'A', 'I8' => 'N'
      }.freeze

      ACTION_CODES = {
        verify: 'VF',
        authorize: 'AU',
        reverse: 'AR'
      }.freeze

      CREDIT_CARD_CODES = {
        american_express: 'AX',
        diners_club: 'DC',
        discover: 'DI',
        jcb: 'JC',
        master: 'MC',
        maestro: 'MI',
        visa: 'VI'
      }.freeze

      RESPONSE_CODES = {
        r000: 'No Answer', r100: 'Approved', r101: 'Validated',
        r102: 'Verified', r103: 'Pre-Noted', r104: 'No Reason to Decline',
        r105: 'Received and Stored', r106: 'Provided Auth',
        r107: 'Request Received', r108: 'Approved for Activation',
        r109: 'Previously Processed Transaction', r110: 'BIN Alert',
        r111: 'Approved for Partial', r164: 'Conditional Approval',
        r200: 'Suspected Fraud', r201: 'Invalid CC Number',
        r202: 'Bad Amount Non-numeric Amount', r203: 'Zero Amount',
        r204: 'Other Error', r205: 'Bad Total Auth Amount',
        r218: 'Invalid SKU Number', r219: 'Invalid Credit Plan',
        r220: 'Invalid Store Number', r225: 'Invalid Field Data',
        r227: 'Missing Companion Data', r231: 'Invalid Division Number',
        r233: 'Does not match MOP', r234: 'Duplicate Order Number',
        r238: 'Invalid Currency', r239: 'Invalid MOP for Division',
        r241: 'Illegal Action', r243: 'Invalid Purchase Level 3',
        r244: 'Invalid Encryption Format',
        r245: 'Missing or Invalid Secure Payment Data',
        r246: 'Merchant not MasterCard Secure code Enabled',
        r248: 'Blanks not passed in reserved field',
        r253: 'Invalid Tran. Type', r260: 'Soft AVS',
        r262: 'Authorization Code Response Date Invalid',
        r263: 'Partial Authorization Not Allowed or Partial Authorization Request Note Valid',
        r274: 'Transaction Not Supported', r303: 'Processor Decline',
        r304: 'Not On File', r305: 'Already Reversed',
        r306: 'Amount Mismatch', r307: 'Authorization Not Found',
        r521: 'Insufficient funds', r522: 'Card is expired',
        r530: 'Do Not Honor', r531: 'CVV2/VAK Failure',
        r591: 'Invalid CC Number', r592: 'Bad Amount',
        r605: 'Invalid Expiration Date', r606: 'Invalid Transaction Type',
        r607: 'Invalid Amount', r811: 'Invalid Security Code'
      }.freeze

      STANDARD_ERROR_CODE_MAPPING = {
        'r201' => STANDARD_ERROR_CODE[:invalid_number],
        'r303' => STANDARD_ERROR_CODE[:card_declined],
        'r521' => STANDARD_ERROR_CODE[:card_declined],
        'r522' => STANDARD_ERROR_CODE[:expired_card],
        'r530' => STANDARD_ERROR_CODE[:card_declined],
        'r531' => STANDARD_ERROR_CODE[:incorrect_cvc],
        'r591' => STANDARD_ERROR_CODE[:invalid_number],
        'r605' => STANDARD_ERROR_CODE[:invalid_expiry_date],
        'r811' => STANDARD_ERROR_CODE[:incorrect_cvc]
      }.freeze

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(amount, credit_card, options = {})
        requires!(options, :order_id, :division_id)

        action = (amount == 0) ? :verify : :authorize
        build_request(action, amount, nil, credit_card, options)
      end

      # purchase, refund, void and capture N/A
      def reverse(amount, authorization, credit_card, options)
        requires!(options, :order_id, :division_id)
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        build_request(:reverse, amount, authorization, credit_card, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(<cmpmsg:AccountNumber>[^<]*</cmpmsg:AccountNumber>), '<cmpmsg:AccountNumber>[FILTERED]</cmpmsg:AccountNumber>').
          gsub(%r(<cmpmsg:CardSecurityValue>[^<]*</cmpmsg:CardSecurityValue>), '<cmpmsg:CardSecurityValue>[FILTERED]</cmpmsg:CardSecurityValue>').
          gsub(%r(Authorization: Basic [a-zA-Z0-9+/=]+), 'Authorization: Basic [FILTERED]')
      end

      private

      def build_request(action, amount, authorization, credit_card, options)
        request = build_base_request do |xml|
          xml.tag! 'cmpapi:Transaction' do
            add_order_id(xml, options)
            add_credit_card(xml, credit_card)
            add_division_id(xml, options)
            add_amount(xml, amount, options)
            add_transaction_info(xml, options)
            xml.tag! 'cmpmsg:ActionCode', ACTION_CODES[action]
          end
          xml.tag! 'cmpapi:AdditionalFormats' do
            add_payment_details(xml, credit_card, options)
            add_customer_info(xml, options)
            add_address(xml, 'AB', options[:billing_address])
            add_address(xml, 'AS', options[:shipping_address])
            add_authorization(xml, authorization) unless authorization.nil?
          end
        end
        commit(request)
      end

      def expdate(credit_card)
        year = format(credit_card.year, :two_digits)
        month = format(credit_card.month, :two_digits)
        "#{month}#{year}"
      end

      def add_order_id(xml, options)
        xml.tag! 'cmpmsg:OrderNumber', truncate(options[:order_id], 22)
      end

      def add_division_id(xml, options)
        xml.tag! 'cmpmsg:DivisionNumber', truncate(options[:division_id], 10)
      end

      def add_transaction_info(xml, options)
        xml.tag! 'cmpmsg:TransactionType', truncate(options[:moto_ecommerce_ind], 1) || '7'
        xml.tag! 'cmpmsg:BillPaymentIndicator', 'N'
      end

      def add_amount(xml, money, options)
        xml.tag! 'cmpmsg:Amount', amount(money)
        xml.tag! 'cmpmsg:CurrencyCode', truncate(options[:currency], 3) || currency(money)
      end

      def add_credit_card(xml, credit_card)
        raise ArgumentError, 'Missing required parameter: credit_card' if credit_card.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:number' if credit_card.number.blank?
        raise ArgumentError, 'Missing required parameter: credit_card:month' if credit_card.month.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:year' if credit_card.year.nil?
        raise ArgumentError, "Unable to determine credit_card brand. Supported values: #{CREDIT_CARD_CODES.keys.join(',')}" unless CREDIT_CARD_CODES.include?(card_brand(credit_card).to_sym)

        xml.tag! 'cmpmsg:Mop', CREDIT_CARD_CODES[card_brand(credit_card).to_sym]
        xml.tag! 'cmpmsg:AccountNumber', credit_card.number
        xml.tag! 'cmpmsg:ExpirationDate', expdate(credit_card)
      end

      def add_payment_details(xml, credit_card, options)
        if credit_card.first_name? && credit_card.last_name?
          xml.tag! 'cmpmsg:LN' do
            xml.tag! 'cmpmsg:FirstName', credit_card.first_name
            xml.tag! 'cmpmsg:LastName', credit_card.last_name
          end
        end

        if credit_card.verification_value?
          xml.tag! 'cmpmsg:FR' do
            xml.tag! 'cmpmsg:CardSecurityValue', credit_card.verification_value
            xml.tag! 'cmpmsg:CardSecurityPresence', options[:csc_indicator] || '1'
          end
        end
      end

      def add_customer_info(xml, options)
        if options[:ip].present?
          xml.tag! 'cmpmsg:AI' do
            xml.tag! 'cmpmsg:AddressSubType', 'B'
            xml.tag! 'cmpmsg:CustomerIPAddress', truncate(options[:ip], 45)
          end
        end

        if options[:email].present?
          xml.tag! 'cmpmsg:AL' do
            xml.tag! 'cmpmsg:AddressSubType', 'B'
            xml.tag! 'cmpmsg:EmailAddress', truncate(options[:email], 50)
          end
        end
      end

      def add_address(xml, element, address)
        return if address.nil?

        xml.tag! "cmpmsg:#{element}" do
          xml.tag! 'cmpmsg:TelephoneNumber', truncate(address[:phone], 14) if address[:phone].present?
          xml.tag! 'cmpmsg:NameText', truncate(address[:name], 30) if address[:name].present?
          xml.tag! 'cmpmsg:Address1', truncate(address[:address1], 30) if address[:address1].present?
          xml.tag! 'cmpmsg:Address2', truncate(address[:address2], 28) if address[:address2].present?
          xml.tag! 'cmpmsg:CountryCode', truncate(address[:country], 2) if address[:country].present?
          xml.tag! 'cmpmsg:City', truncate(address[:city], 20) if address[:city].present?
          xml.tag! 'cmpmsg:State', truncate(address[:state], 2) if address[:state].present?
          xml.tag! 'cmpmsg:PostalCode', truncate(address[:zip], 10) if address[:zip].present?
        end
      end

      def add_authorization(xml, authorization)
        auth_code, auth_date = authorization.to_s.split(';')
        xml.tag! 'cmpmsg:PA' do
          xml.tag! 'cmpmsg:ResponseDate', auth_date
          xml.tag! 'cmpmsg:AuthorizationCode', auth_code
        end
      end

      def build_base_request
        xml = Builder::XmlMarkup.new

        xml.instruct!
        xml.tag! 'soapenv:Envelope', ENVELOPE_NAMESPACES do
          xml.tag! 'soapenv:Header'
          xml.tag! 'soapenv:Body' do
            xml.tag! 'cmpapi:OnlineTransRequest', REQUEST_NAMESPACES do
              yield(xml)
            end
          end
        end
        xml.target!
      end

      def commit(request)
        url = test? ? test_url : live_url
        response = parse(ssl_post(url, request, headers))

        Response.new(successful?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response),
          fraud_review: fraud_review?(response),
          avs_result: { code: AVS_CODE_TRANSLATOR[response[:AVSResponseCode]] },
          cvv_result: response[:CSVResponseCode],
          error_code: standard_error_code_from(response))
      end

      def parse(xml)
        reply = {}
        xml = REXML::Document.new(xml)
        if (root = REXML::XPath.first(xml, '//ns3:OnlineTransResponse'))
          parse_element(reply, root)
        elsif (root = REXML::XPath.first(xml, '//SOAP-ENV:Fault'))
          parse_element(reply, root)
          reply[:message] = reply[:faultstring].to_s
        end
        reply
      end

      def parse_element(reply, node)
        if node.name == 'detail'
          node.elements.each_with_index { |e, i| reply["#{e.name}_#{i}".to_sym] = e.text.to_s.strip }
        elsif node.has_elements?
          node.elements.each { |e| parse_element(reply, e) }
        else
          reply[node.name.to_sym] = node.text.to_s.strip
        end
        reply.delete_if { |k, _v| SENSITIVE_FIELDS.include?(k) }
        reply
      end

      def authorization_from(response)
        return nil if response[:AuthorizationCode].blank?

        [response[:AuthorizationCode], response[:ResponseDate]].join(';')
      end

      def fraud_review?(response)
        response[:ResponseReasonCode] == FRAUD_CODE
      end

      def successful?(response)
        return false if response[:ResponseReasonCode].nil?

        response[:ResponseReasonCode].to_i >= 100 && response[:ResponseReasonCode].to_i < 200
      end

      def message_from(response)
        if response[:faultstring]
          response[:faultstring]
        else
          key = "r#{response[:ResponseReasonCode]}".to_sym rescue nil
          RESPONSE_CODES[key] || "Response Reason Code: #{response[:ResponseReasonCode]}"
        end
      end

      def standard_error_code_from(response)
        return nil if successful?(response)

        key = "r#{response[:ResponseReasonCode]}" rescue nil
        STANDARD_ERROR_CODE_MAPPING[key] || STANDARD_ERROR_CODE[:processing_error]
      end

      def headers
        {
          'Authorization' => 'Basic ' + Base64.strict_encode64("#{@options[:login]}:#{@options[:password]}").chomp,
          'Content-Type' => 'text/xml',
          'Accepts' => 'application/xml'
        }
      end

      def truncate(value, max_size)
        return nil unless value

        value.to_s[0, max_size]
      end
    end
  end
end
