module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class ChaseNetConnectGateway < Gateway
      class_attribute :actions, :test_url_secondary, :live_url_secondary

      self.test_url = 'https://netconnectvar1.chasepaymentech.com/NetConnect/controller'
      self.test_url_secondary = 'https://netconnectvar2.chasepaymentech.com/NetConnect/controller'
      self.live_url = 'https://netconnect1.paymentech.net/NetConnect/controller'
      self.live_url_secondary = 'https://netconnect2.paymentech.net/NetConnect/controller'

      self.supported_countries = ['US', 'CA']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :jcb]
      self.homepage_url = 'https://www.chase.com/'
      self.display_name = 'Chase NetConnect'
      self.money_format = :cents

      CHASE_VENDOR_ID   = '00C7'
      CHASE_SOFTWARE_ID = '0129'

      self.actions = {
        authorize: '02',
        purchase: '01',
        capture: '03',
        void: '41',
        refund: '06',
        partial_auth_reverse: '09',
        reverse_advice: '46'
      }.freeze

      RESPONSE_FIELDS = [
        [:fixed_data, 0],
        [:interchange, 1],
        [:auth_network_source, 2],
        [:optional_data, 4]
      ].freeze

      RESPONSE_FIELDS_FIXED = [
        [:action_code, 0, 1],
        [:avs_performed, 1, 1],
        [:response_code, 2, 6],
        [:batch_number, 8, 6],
        [:reference_number, 14, 8],
        [:sequence_number, 22, 6],
        [:message, 28, 32],
        [:card_type, 60, 2]
      ].freeze

      FS  = "\x1C"
      STX = "\x02"
      ETX = "\x03"

      STANDARD_ERROR_CODE_MAPPING = {
        'D' => STANDARD_ERROR_CODE[:card_declined]
      }.freeze

      def initialize(options = {})
        requires!(options, :login, :password, :mid, :cid, :tid)
        super
      end

      def authorize(money, creditcard, options = {})
        commit_sale_auth_refund(:authorize, money, creditcard, options)
      end

      def purchase(money, creditcard, options = {})
        commit_sale_auth_refund(:purchase, money, creditcard, options)
      end

      def capture(money, authorization, options = {})
        creditcard = options[:credit_card]
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?

        commit_capture_partial_reverse(:capture, money, authorization, creditcard, options)
      end

      def reverse(money, authorization, creditcard, options = {})
        if options[:partial_auth_reverse] == '1'
          commit_capture_partial_reverse(:partial_auth_reverse, money, authorization, creditcard, options)
        else
          commit_reverse_advice(money, authorization, creditcard, options)
        end
      end

      def void(authorization, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        creditcard = options[:credit_card]
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?

        _, ref_num = split_authorization(authorization)
        raise ArgumentError, 'Authorization field is not in the correct format' if ref_num.nil?

        post = ''
        add_preamble(post, :void)
        post << ref_num
        post << FS
        post << ref_num
        post << FS
        add_creditcard_num(post, creditcard)
        post << 'TAY' # Token allowed
        post << FS
        add_cdd(post, options)
        post << ETX

        commit(post, :void)
      end

      def refund(money, authorization, options = {})
        creditcard = options[:credit_card]
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?

        commit_sale_auth_refund(:refund, money, creditcard, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(Auth-Password: [^\s]+), 'Auth-Password: [FILTERED]').
          gsub(%r(Auth-User: [^\s]+), 'Auth-User: [FILTERED]').
          gsub(%r(#{Regexp.escape(STX)}[^\x03]*#{Regexp.escape(ETX)})m, '[FILTERED_BINARY_DATA]')
      end

      private

      def commit_sale_auth_refund(action, money, creditcard, options = {})
        requires!(options, :order_id)

        post = ''
        add_preamble(post, action)

        post << '2' # Pin code
        post << '02' # Entry data source
        add_creditcard(post, creditcard) # FS1
        add_amount(post, money) # FS2
        post << FS # FS3
        post << '00000000' # Filler
        post << FS # FS4
        post << FS # FS5
        post << FS # FS6
        post << '013' # industry code
        post << format_order_id(options[:order_id])
        post << (options[:eci].present? ? options[:eci].ljust(2, '0') : '08')
        post << options[:goods_type].ljust(2, ' ').upcase if options[:goods_type].present?
        post << FS # FS7
        post << FS # FS8
        post << FS # FS9
        add_card_billing_address(post, options) # FS10,11
        post << FS # FS12
        add_cvv(post, creditcard, options)
        add_cdd(post, options)
        add_cavv(post, creditcard, options)
        add_rn(post, options)
        add_p8(post, options)
        add_p1p2(post)
        post << ETX

        commit(post, action, money, creditcard, options)
      end

      def commit_capture_partial_reverse(action, money, authorization, creditcard, options = {})
        requires!(options, :order_id)
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        authcode, _ = split_authorization(authorization)

        post = ''
        add_preamble(post, action)

        post << '2' # Pin code
        post << '02' # Entry data source
        add_creditcard(post, creditcard) # FS1
        add_amount(post, money) # FS2
        post << FS # FS3
        post << '00000000' # Filler
        post << FS # FS4
        post << FS # FS5
        post << FS # FS6
        post << '013' # industry code
        post << format_order_id(options[:order_id])
        post << (options[:eci].present? ? options[:eci].ljust(2, '0') : '08')
        post << options[:goods_type].ljust(2, ' ').upcase if options[:goods_type].present?
        post << FS # FS7
        post << authcode
        post << FS # FS8
        if action == :capture
          post << FS # FS9
          post << FS # FS10
          post << FS # FS11
          post << FS # FS12
          add_cdd(post, options)
        end
        post << ETX

        commit(post, action)
      end

      def commit_reverse_advice(money, authorization, creditcard, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        _, _, reverse_type = split_authorization(authorization)
        requires!(options, :order_id)

        post = ''
        add_preamble(post, :reverse_advice)
        post << '2' # Pin code
        post << '02' # Entry data source
        add_creditcard(post, creditcard) # FS1
        add_amount(post, money) # FS2
        post << FS # FS3
        post << FS # FS4
        post << FS # FS5
        post << FS # FS6
        post << FS # FS7
        post << FS # FS8
        post << FS # FS9
        post << FS # FS10
        post << FS # FS11
        post << FS # FS12
        add_rn(post, options)
        add_tc(post, reverse_type)
        add_p1p2(post)
        post << ETX

        commit(post, :reverse_advice)
      end

      def add_preamble(post, action)
        post << STX
        post << 'L.' # Host capture
        post << 'A02000' # Routing indicator
        post << @options[:cid].rjust(4, '0')
        post << @options[:mid].rjust(12, '0')
        post << @options[:tid].rjust(3, '0')
        post << '1' # Single transaction
        post << '000001' # Sequence number
        post << 'F' # Transaction class
        post << self.actions[action]
      end

      def add_creditcard(post, creditcard)
        add_creditcard_num(post, creditcard)
        add_creditcard_exp(post, creditcard)
      end

      def add_creditcard_num(post, creditcard)
        raise ArgumentError, 'Missing required parameter: credit_card:number' if creditcard.number.blank?

        post << creditcard.number
        post << FS
      end

      def add_creditcard_exp(post, creditcard)
        raise ArgumentError, 'Missing required parameter: credit_card:month' if creditcard.month.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:year' if creditcard.year.nil?

        post << expdate(creditcard)
        post << FS
      end

      def expdate(creditcard)
        year  = sprintf('%.4i', creditcard.year)
        month = sprintf('%.2i', creditcard.month)
        "#{month}#{year[2..3]}"
      end

      def add_cvv(post, creditcard, options)
        unless options[:user_data_1]
          post << 'CV'
          post << 'PI'
          if creditcard.verification_value?
            post << '1'
            post << 'VF'
            post << creditcard.verification_value.length.to_s
            post << creditcard.verification_value
          else
            post << '9'
          end
          post << FS
        end
      end

      def add_cdd(post, options)
        requires!(options, :order_id)
        post << 'CD'
        post << format_order_id(options[:order_id], 30)
        post << FS
      end

      def add_cavv(post, creditcard, options)
        if options[:cavv].present?
          case creditcard.brand
          when 'visa'
            post << 'VA'
            post << format_cavv(options[:cavv])
            post << FS
          when 'master'
            post << 'SC'
            post << '2'
            post << options[:cavv]
            post << FS
          end
        end
      end

      def add_rn(post, options)
        requires!(options, :order_id)
        post << 'RN'
        post << format_order_id(options[:order_id], 12)
        post << FS
      end

      def add_p8(post, options)
        post << 'P8'
        post << (options[:authorization_type].present? ? options[:authorization_type][0, 2] : '00')
        post << FS
      end

      def add_p1p2(post)
        post << 'P1'
        post << CHASE_VENDOR_ID
        post << CHASE_SOFTWARE_ID
        post << '1'.ljust(20, ' ')
        post << FS

        post << 'P2'
        post << '62A0000000000000'
        post << '0840102048'
        post << FS
      end

      def add_tc(post, reverse_type)
        post << 'TC'
        post << reverse_type unless reverse_type.nil?
        post << FS
      end

      def add_amount(post, money)
        post << amount(money)
      end

      def add_card_billing_address(post, options)
        if (address = options[:billing_address] || options[:address])
          post << address[:address1][0, 20].upcase if address[:address1].present?
          post << address[:address2][0, 20].upcase if address[:address2].present?
          post << FS
          post << address[:zip][0, 9] if address[:zip].present?
          post << FS
        else
          post << FS
          post << FS
        end
      end

      def format_order_id(order_id, len = 16)
        order_id = '' if order_id.nil?
        illegal_characters = /[^\.\/,$@\-\w]/
        order_id = order_id.gsub(illegal_characters, '')
        order_id[0, len].ljust(len, ' ').upcase
      end

      def format_cavv(cavv)
        encoded = cavv.unpack1('m').unpack1('H*')
        raise ArgumentError, 'Invalid CAVV format or value' unless encoded.length == 40

        encoded
      end

      def commit(post_data, action, money = 0, creditcard = nil, options = {})
        request = lambda { |url| parse(ssl_post(url, post_data, header_data)) }

        response = nil
        failover = false
        begin
          response = begin
            request.call(remote_url(:primary))
          rescue ConnectionError
            failover = true
            request.call(remote_url(:secondary))
          end
        rescue ResponseError => e
          params = {}
          params[:error_code] = e.response['Error-Code'] if e.response['Error-Code'].present?
          params[:error_reason] = e.response['Error-Reason'] if e.response['Error-Reason'].present?

          if %w[506 509 515 516 517].include?(e.response['Error-Code']) && [:authorize, :purchase].include?(action)
            commit_reverse_advice(money, authorization_from(e.response, action), creditcard, options)
          end

          return Response.new(false,
            (params[:error_reason].present? ? params[:error_reason] : e.response.body),
            params,
            test: test?,
            authorization: authorization_from(e.response, action))
        end

        Response.new(success?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response, action),
          avs_result: { code: response[:avs_performed] },
          cvv_result: response[:token_CV],
          failover: failover,
          error_code: success?(response) ? nil : STANDARD_ERROR_CODE[:processing_error])
      end

      def success?(response)
        response[:action_code] == 'A'
      end

      def message_from(response)
        response[:message]
      end

      def authorization_from(response, action)
        "#{response[:response_code]};#{response[:reference_number]};#{self.actions[action]}"
      end

      def split_authorization(auth)
        auth.to_s.split(';')
      end

      def remote_url(url = :primary)
        if url == :primary
          test? ? self.test_url : self.live_url
        else
          test? ? self.test_url_secondary : self.live_url_secondary
        end
      end

      def header_data
        headers = {
          'Auth-MID' => @options[:mid],
          'Auth-User' => @options[:login],
          'Auth-Password' => @options[:password],
          'Header-Record' => 'false',
          'Stateless-Transaction' => 'true',
          'Content-Type' => 'UTF197/HCS'
        }
        headers['Auth-TID'] = @options[:tid] if @options[:tid].present?
        headers
      end

      def parse(response)
        raise StandardError unless response.start_with?(STX) && response.end_with?(ETX)

        response = response.sub(STX, '').sub(ETX, '')

        parsed = {}

        delim_response = response.split(FS)
        RESPONSE_FIELDS.each do |param|
          parsed[param[0]] = delim_response[param[1]]
        end

        RESPONSE_FIELDS_FIXED.each do |param|
          parsed[param[0]] = parsed[:fixed_data][param[1], param[2]].strip
        end
        parsed.delete(:fixed_data)

        tokens = delim_response[10..-1]
        unless tokens.nil?
          tokens.each do |token|
            parsed["token_#{token[0, 2]}".to_sym] = token[2..-1] if token.length >= 3
          end
        end

        parsed
      end
    end
  end
end
