module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class EpxGateway < Gateway
      self.test_url = 'https://secure.epxuap.com'
      self.live_url = 'https://secure.epx.com'

      self.money_format = :dollars
      self.default_currency = 'USD'
      self.supported_countries = ['US']
      self.supported_cardtypes = %i[visa master american_express discover]

      self.homepage_url = 'http://www.epx.com'
      self.display_name = 'Electronic Payment Exchange (EPX)'

      TRANSACTION_TYPES = {
        sale: 'CCE1',
        authorization: 'CCE2',
        capture: 'CCE4',
        void: 'CCEX',
        credit: 'CCE9',
        reverse: 'CCE7',
        checkSale: 'CKC2',
        savingsSale: 'CKS2',
        checkVoid: 'CKCX',
        savingsVoid: 'CKSX',
        checkCredit: 'CKC3',
        savingsCredit: 'CKS3'
      }

      def initialize(options = {})
        # cust_nbr = cid
        # merch_nbr = mid
        # dba_nbr = subid
        # terminal_nbr = tid
        requires!(options, :cid, :mid, :subid, :tid)
        @options = options
        super
      end

      def authorize(money, payment_method, options = {})
        build_sale_or_authorization_request(:authorization, money, payment_method, options)
      end

      def purchase(money, payment_method, options = {})
        build_sale_or_authorization_request(:sale, money, payment_method, options)
      end

      def capture(money, authorization, options = {})
        build_capture_void_reverse_request(:capture, money, authorization, options)
      end

      def void(authorization, options = {})
        build_capture_void_reverse_request(:void, nil, authorization, options)
      end

      def refund(money, authorization, options = {})
        if options.include?(:credit_card)
          payment_method = options[:credit_card]
          build_sale_or_authorization_request(:credit, money, payment_method, options)
        else
          raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

          post = {}
          add_amount(post, money, options)
          add_trans_id(post, options)
          add_authorization(post, authorization)

          _, kind = split_authorization(authorization)
          if kind == 'checkSale'
            action = :checkCredit
          elsif kind == 'savingsSale'
            action = :savingsCredit
          else
            action = :credit
          end

          commit(action, post, options[:moto_ecommerce_ind])
        end
      end

      def reverse(amount, authorization, payment_method, options)
        build_capture_void_reverse_request(:reverse, nil, authorization, options)
      end

      def supports_check?
        true
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(/(ACCOUNT_NBR=)[^&]*/, '\1[FILTERED]').
          gsub(/(CVV2=)[^&]*/, '\1[FILTERED]').
          gsub(/(ROUTING_NBR=)[^&]*/, '\1[FILTERED]').
          gsub(/(password=)[^&]*/, '\1[FILTERED]')
      end

      private

      def build_sale_or_authorization_request(action, money, payment_method, options)
        post = {}

        add_amount(post, money, options)
        add_trans_id(post, options)
        if card_brand(payment_method) == 'check'
          add_check(post, payment_method, options)
          if action == :credit
            action = (payment_method.account_type.to_s.downcase == 'savings') ? :savingsCredit : :checkCredit
          else
            action = (payment_method.account_type.to_s.downcase == 'savings') ? :savingsSale : :checkSale
          end
        else
          add_credit_card(post, payment_method, options)
        end
        add_address(post, options)
        add_userdata(post, options)

        commit(action, post, options[:moto_ecommerce_ind])
      end

      def build_capture_void_reverse_request(action, money, authorization, options)
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        _, kind = split_authorization(authorization)
        if kind == 'checkSale' || kind == 'savingsSale'
          raise ArgumentError, 'This transaction type is not supported for checks' unless action == :void

          action = (kind == 'checkSale') ? :checkVoid : :savingsVoid
        end

        post = {}

        add_amount(post, money, options) unless money.nil?
        add_trans_id(post, options)
        add_authorization(post, authorization)

        commit(action, post, options[:moto_ecommerce_ind])
      end

      def add_authorization(post, ident)
        guid, _ = split_authorization(ident)
        post[:ORIG_AUTH_GUID] = guid
        post[:CARD_ENT_METH] = 'Z'
      end

      def add_amount(post, money, options)
        post[:AMOUNT] = amount(money)
        post[:CURRENCY_CODE] = options[:currency] if options[:currency].present?
      end

      def add_credit_card(post, credit_card, options)
        post[:ACCOUNT_NBR] = credit_card.number
        post[:EXP_DATE] = epx_expdate(credit_card)
        post[:CVV2] = credit_card.verification_value
        post[:FIRST_NAME] = credit_card.first_name
        post[:LAST_NAME] = credit_card.last_name
        post[:CARD_ENT_METH] = 'X'
      end

      def add_check(post, check, options)
        post[:CHECK_NBR] = check.number if check.number.present?
        post[:ACCOUNT_NBR] = check.account_number
        post[:ROUTING_NBR] = check.routing_number
        post[:FIRST_NAME] = options[:first_name]
        post[:LAST_NAME] = options[:last_name]
        post[:CARD_ENT_METH] = 'X'
      end

      def add_trans_id(post, options)
        post[:BATCH_ID] = options[:report_group]
        post[:TRAN_NBR] = options[:transaction_index]
      end

      def add_address(post, options)
        if address = (options[:billing_address] || options[:address])
          post[:ADDRESS] = address[:address1]
          post[:CITY] = address[:city]
          post[:STATE] = address[:state]
          post[:ZIP_CODE] = address[:zip]
        end
      end

      def add_userdata(post, options)
        post[:CARD_ID] = options[:card_present_code] if options[:card_present_code].present?
        post[:INVOICE_NBR] = options[:invoice_number] if options[:invoice_number].present?
        post[:ORDER_NBR] = options[:order_id] if options[:order_id].present?

        post[:USER_DATA_1] = options[:user_data_1] if options[:user_data_1].present?
        post[:USER_DATA_2] = options[:user_data_2] if options[:user_data_2].present?
        post[:USER_DATA_3] = options[:user_data_3] if options[:user_data_3].present?
        post[:USER_DATA_4] = options[:user_data_4] if options[:user_data_4].present?
        post[:USER_DATA_5] = options[:user_data_5] if options[:user_data_5].present?
      end

      def post_data(action, params = {}, moto_ind = nil)
        params[:cust_nbr] = @options[:cid]
        params[:merch_nbr] = @options[:mid]
        params[:dba_nbr] = @options[:subid]
        params[:terminal_nbr] = @options[:tid]

        params[:TRAN_TYPE] = TRANSACTION_TYPES[action]
        if !moto_ind.nil? && moto_ind =~ /MOTO/i
          params[:TRAN_TYPE] = params[:TRAN_TYPE].gsub('E', 'M')
        end

        params.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
      end

      def epx_expdate(credit_card)
        "#{format(credit_card.year, :two_digits)}#{format(credit_card.month, :two_digits)}"
      end

      def commit(action, request, moto_ind = nil)
        url = (test? ? self.test_url : self.live_url)
        response = parse(ssl_post(url, post_data(action, request, moto_ind)))

        Response.new(successful?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(action, response),
          avs_result: { code: response[:auth_avs] },
          cvv_result: response[:auth_cvv2]
        )
      end

      def successful?(response)
        response[:auth_resp] == '00'
      end

      def split_authorization(authorization)
        transaction_id, kind = authorization.to_s.split(';')
        [transaction_id, kind]
      end

      def authorization_from(action, response)
        "#{response[:auth_guid]};#{action}"
      end

      def message_from(response)
        response[:auth_resp_text]
      end

      def parse(xml)
        response = {}
        xml = REXML::Document.new(xml)

        if root = REXML::XPath.first(xml, '//FIELDS')
          parse_elements(response, root)
        end
        response
      end

      def parse_elements(response, root)
        root.elements.to_a.each do |node|
          response[node.attributes['KEY'].underscore.to_sym] = (node.text || '').strip
        end
      end
    end
  end
end
