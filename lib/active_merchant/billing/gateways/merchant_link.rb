module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # Merchant Link TV2G Payment Gateway
    class MerchantLinkGateway < Gateway
      class_attribute :secondary_test_url, :secondary_live_url

      self.test_url = 'https://tv1var.merchantlink-lab.com:8184/TV2G'
      self.secondary_test_url = 'https://tv2var.merchantlink-lab.com:8185/TV2G'

      self.live_url = 'https://tv1var.merchantlink.com:8184/TV2G'
      self.secondary_live_url = 'https://tv2var.merchantlink.com:8185/TV2G'

      self.money_format = :dollars
      self.homepage_url = 'http://www.merchantlink.com'
      self.display_name = 'Merchant Link TV2G Payment Gateway'

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      API_VERSION = '200'

      POST_HEADERS = {
        'User-Agent' => 'TokenEx/v1 PaymentGatewayBindings',
        'Content-Type' => 'text/xml'
      }

      AVS_STREET_MATCH = {
        '0' => 'N',
        '1' => 'Y',
        '2' => 'Y',
        '3' => nil,
        '4' => nil,
        'E' => nil,
        'G' => 'X',
        'H' => nil,
        'R' => nil,
        'S' => 'X',
        'U' => nil
      }

      AVS_POSTAL_MATCH = {
        '0' => 'N',
        '1' => 'Y',
        '2' => 'Y',
        '3' => nil,
        '4' => nil,
        '5' => 'Y',
        '9' => 'Y',
        'E' => nil,
        'G' => 'X',
        'H' => nil,
        'R' => nil,
        'S' => 'X',
        'U' => nil
      }

      def initialize(options = {})
        requires!(options, :login, :subid)
        super
      end

      def authorize(money, credit_card, options = {})
        order = build_authorize_sale(:CCAuth, money, credit_card, options)
        commit(order)
      end

      def purchase(money, credit_card, options = {})
        order = build_authorize_sale(:CCSale, money, credit_card, options)
        commit(order)
      end

      def capture(money, authorization, options = {})
        order = build_capture_void(:CCCapture, money, authorization, options)
        commit(order)
      end

      def refund(money, authorization, options = {})
        raise ArgumentError, 'Missing required parameter: credit_card' unless options.include?(:credit_card)
        credit_card = options[:credit_card]

        order = build_request_xml(:CCRefund, options) do |xml|
          add_credit_card(xml, credit_card)
          xml.tag! :TranAmt, amount(money)
          add_mode(xml, options)
          unless authorization.nil?
            ml_tran_id, _ = split_authorization(authorization)
            xml.tag! :MLTranID, ml_tran_id.to_s
          end
        end
        commit(order)
      end

      def void(authorization, options = {})
        order = build_capture_void(:CCVoid, nil, authorization, options)
        commit(order)
      end

      def reverse(money, authorization, credit_card, options = {})
        requires!(options, :prior_transaction_index, :prior_posts, :prior_tranaction_type)
        raise ArgumentError, 'Missing required parameter: credit_card' if credit_card.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:number' if credit_card.number.blank?

        order = build_request_xml(:CCTimeout, options) do |xml|
          xml.tag! :PriorPOSTranID, options[:prior_transaction_index]
          xml.tag! :PriorPOSTS, options[:prior_posts]
          xml.tag! :PriorTranType, options[:prior_tranaction_type]
          xml.tag! :PAN, credit_card.number
          xml.tag! :TranAmt, amount(money)
        end
        commit(order)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(<PAN>[^<]*</PAN>)i, '<PAN>[FILTERED]</PAN>').
          gsub(%r(<Exp>[^<]*</Exp>)i, '<Exp>[FILTERED]</Exp>').
          gsub(%r(<CVD>[^<]*</CVD>)i, '<CVD>[FILTERED]</CVD>').
          gsub(%r(<T1>[^<]*</T1>)i, '<T1>[FILTERED]</T1>').
          gsub(%r(<T2>[^<]*</T2>)i, '<T2>[FILTERED]</T2>')
      end

      private

      def build_authorize_sale(action, money, credit_card, options = {})
        order = build_request_xml(action, options) do |xml|
          add_credit_card(xml, credit_card)
          xml.tag! :TranAmt, amount(money)
          add_mode(xml, options)
          add_basic_address(xml, options)
          add_cvd(xml, credit_card)
        end
        order
      end

      def build_capture_void(action, money, authorization, options = {})
        ml_tran_id, tv_key = split_authorization(authorization)

        order = build_request_xml(action, options) do |xml|
          xml.tag! :MLTranID, ml_tran_id.to_s
          xml.tag! :Last4, tv_key.to_s
          xml.tag! :TranAmt, amount(money) unless money.nil?
        end
        order
      end

      def authorization_string(ml_tran_id, tv_key)
        tv_key = tv_key[-4, 4] unless tv_key.nil?
        [ml_tran_id, tv_key].join(';')
      end

      def split_authorization(authorization)
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?
        authorization.to_s.split(';')
      end

      def add_basic_address(xml, options)
        if (address = (options[:billing_address] || options[:address]))
          xml.tag! :Address, (address[:address1] ? address[:address1][0..19] : nil)
          xml.tag! :Zip, (address[:zip] ? address[:zip].to_s[0..9] : nil)
        end
      end

      def add_mode(xml, options)
        xml.tag! :Mode do
          xml.tag! :MOTOECI, options[:moto_ecommerce_ind] || '0'
          xml.tag! :InputMethod, options[:input_method] || 'K'
          xml.tag! :InputCap, options[:input_capability] || 'B'
          xml.tag! :AuthMethod, options[:authentication_method] || 'S'
          xml.tag! :OpEnv, options[:operating_environment] || '1'
          xml.tag! :PINCap, options[:pin_capability] || 'N'
          xml.tag! :OutputCap, options[:output_capability] || 'B'
        end
      end

      def add_credit_card(xml, credit_card)
        raise ArgumentError, 'Missing required parameter: credit_card' if credit_card.nil?
        xml.tag! :CCData do
          if credit_card.respond_to?(:track_1_data) && credit_card.track_1_data.present?
            xml.tag! :T1, credit_card.track_1_data
          elsif credit_card.respond_to?(:track_2_data) && credit_card.track_2_data.present?
            xml.tag! :T2, credit_card.track_2_data
          else
            raise ArgumentError, 'Missing required parameter: credit_card:number' if credit_card.number.blank?
            raise ArgumentError, 'Missing required parameter: credit_card:month' if credit_card.month.nil?
            raise ArgumentError, 'Missing required parameter: credit_card:year' if credit_card.year.nil?

            xml.tag! :PAN, credit_card.number
            xml.tag! :Exp, expiry_date(credit_card)
          end
        end
      end

      def add_cvd(xml, credit_card)
        raise ArgumentError, 'Missing required parameter: credit_card' if credit_card.nil?
        if credit_card.verification_value?
          xml.tag! :CVDInd, '1'
          xml.tag! :CVD, credit_card.verification_value
        else
          xml.tag! :CVDInd, '0'
        end
      end

      def parse(body)
        response = {}
        xml = REXML::Document.new(body)
        root = REXML::XPath.first(xml, '//CreditResp')
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

      def commit(order)
        headers = POST_HEADERS.merge('Content-length' => order.size.to_s)

        failover = false
        response = nil
        begin
          response = parse(ssl_post(remote_url, order, headers))
        rescue ConnectionError
          failover = true
        end

        if failover
          response = parse(ssl_post(remote_url(:secondary), order, headers))
          failover = true
        end

        Response.new(success?(response), message_from(response), response,
          {
            authorization: authorization_string(response[:ml_tran_id], response[:tv_key]),
            test: self.test?,
            avs_result: {
              postal_match: AVS_POSTAL_MATCH[response[:zip_result]],
              street_match: AVS_STREET_MATCH[response[:address_result]]
            },
            cvv_result: response[:cvd_result],
            failover: failover
          }
        )
      end

      def remote_url(url = :primary)
        if url == :primary
          (self.test? ? self.test_url : self.live_url)
        else
          (self.test? ? self.secondary_test_url : self.secondary_live_url)
        end
      end

      def success?(response)
        response[:ml_resp_code].to_s.start_with?('A')
      end

      def message_from(response)
        response[:ml_resp_text] || response[:host_resp_text]
      end

      def build_request_xml(action, parameters = {})
        requires!(parameters, :terminal_id, :lane_id, :transaction_index, :date, :time, :posts)

        xml = xml_envelope
        xml.tag! :TV2G, 'VID' => API_VERSION do
          xml.tag! :Comp, @options[:login]
          xml.tag! :Site, @options[:subid]
          xml.tag! :Term, parameters[:terminal_id]
          xml.tag! :Lane, parameters[:lane_id]
          xml.tag! :POSTranID, parameters[:transaction_index]

          xml.tag! :Credit do
            xml.tag! :Version, parameters[:pos_version] || 'TokenEx v2.1 Payment Gateway'
            xml.tag! :POSTS, parameters[:posts]
            xml.tag! :LocalTranDate, parameters[:date]
            xml.tag! :LocalTranTime, parameters[:time]
            xml.tag! :Check, format_order_id(parameters[:order_id]) if parameters[:order_id].present?

            xml.tag! action do
              yield xml if block_given?
            end
          end
        end
        xml.target!
      end

      def expiry_date(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :two_digits)}"
      end

      def xml_envelope
        xml = Builder::XmlMarkup.new(indent: 2)
        xml.instruct!(:xml, version: '1.0', encoding: 'US-ASCII')
        xml
      end

      def format_order_id(order_id)
        order_id[0...20]
      end
    end
  end
end
