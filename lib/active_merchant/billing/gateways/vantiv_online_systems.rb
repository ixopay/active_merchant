module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class VantivOnlineSystemsGateway < Gateway
      include Empty
      class_attribute :actions, :FS, :GS, :RS,
                      :approved_response_fields_fixed,
                      :error_response_fields_fixed,
                      :approved_token_convert_fields_fixed

      self.test_url = 'https://cert.protectedtransactions.com/AUTH'
      self.live_url = 'https://prod.protectedtransactions.com/AUTH'

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club]
      self.homepage_url = 'https://www.vantiv.com/'
      self.display_name = 'Vantiv Online Systems (610)'
      self.money_format = :cents

      self.actions = {
        authorize: '010021004000',
        authorize_avs: '010025524000',
        purchase: '020022004000',
        purchase_avs: '020025524000',
        capture: '022024004000',
        void: '040001',
        refund: '020022204000',
        reverse: '010009224000',
        token_convert: '010050800000'
      }.freeze

      self.FS = "\x1C" # Field separator
      self.GS = "\x1D" # Group separator
      self.RS = "\x1E" # Record separator

      self.approved_response_fields_fixed = [
        [:processing_code, 6, 6],
        [:transmission_date_time, 12, 10],
        [:stan, 22, 6],
        [:retrieval_reference, 28, 8],
        [:authorization, 36, 6],
        [:avs_response, 42, 2],
        [:payment_service_indicator, 44, 1],
        [:transaction_identifier, 45, 15],
        [:visa_validation_code, 60, 4],
        [:trace_data, 64, 16],
        [:batch_number, 80, 6],
        [:demo_merchant_flag, 86, 1],
        [:card_type, 87, 4],
        [:working_key, 91, 16]
      ].freeze

      self.approved_token_convert_fields_fixed = [
        [:processing_code, 6, 6],
        [:transmission_date_time, 12, 10],
        [:stan, 22, 6],
        [:trace_data, 28, 16],
        [:batch_number, 44, 6],
        [:demo_merchant_flag, 50, 1]
      ].freeze

      self.error_response_fields_fixed = [
        [:stan, 6, 6],
        [:avs_response, 12, 2],
        [:payment_service_indicator, 14, 1],
        [:transaction_identifier, 15, 15],
        [:visa_validation_code, 30, 4],
        [:trace_data, 34, 16],
        [:error_text, 50, 20],
        [:response_code, 70, 3],
        [:working_key, 73, 16]
      ].freeze

      def initialize(options = {})
        requires!(options, :login, :password, :mid, :bid, :tid)
        @station_id = options[:station_id] || ('0' * 15)
        super
      end

      def authorize(money, creditcard, options = {})
        if options[:authorization_type].to_s =~ /token_convert/i
          commit_token_conversion(creditcard, options)
        else
          action = options[:billing_address].nil? ? :authorize : :authorize_avs
          commit_auth_or_sale(money, creditcard, action, options)
        end
      end

      def purchase(money, creditcard, options = {})
        action = options[:billing_address].nil? ? :purchase : :purchase_avs
        commit_auth_or_sale(money, creditcard, action, options)
      end

      def capture(money, authorization, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        creditcard = options[:credit_card]
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?

        _, auth, ar, psi, ti, vvc = split_authorization(authorization)
        if auth.nil? || auth.empty?
          auth = authorization
          ar = ' ' * 2
          psi = ' '
          ti = ' ' * 15
          vvc = ' ' * 4
        end
        raise ArgumentError, 'Invalid value: authorization' unless auth.present?

        post = ''
        add_preamble(post, :capture)
        add_amount(post, money)
        post << Time.now.strftime('%m%d%y%H%M')
        post << fixed_len(options, :stan, 6)
        post << fixed_len(options, :date, 6)
        post << fixed_len(options, :time, 6)
        post << fixed_len(options, :pos_entry_mode, 3)
        post << fixed_len(options, :pos_condition_code, 10)
        post << fixed_len(@options, :bid, 4)
        post << fixed_len(@options, :tid, 3)
        post << fixed_len(@options, :mid, 12)
        post << fixed_len(options, :lane_id, 3)
        add_creditcard(post, creditcard, options)
        post << fixed_len(options, :additional_data, 8)
        post << fixed_len(options, :clerk, 8)
        post << auth.to_s[0, 6]
        post << '00' # extended payment code
        post << '000' # network management code
        post << ar[0, 2]
        post << psi[0]
        post << ti[0, 15]
        post << vvc[0, 4]
        post << fixed_len(options, :input_capability, 2)
        post << fixed_len(options, :customer, 20, ' ')
        post << fixed_len(options, :tax, 9)
        post << fixed_len(options, :trace, 16, ' ')
        post << self.RS
        add_group(post, 1, options[:order_id])
        add_g2(post, options)
        add_group(post, 3, options[:avv])
        add_group(post, 8, options[:pos_data_code])
        add_g28(post, creditcard, options)
        add_group(post, 45, options[:user_data_1])
        add_g48(post, options) unless options[:api_transaction_id].nil?
        add_g58(post, options[:shipping_address], options) unless options[:shipping_address].nil?
        add_g60(post, options) unless options[:ip].nil?
        commit(post)
      end

      def reverse(money, authorization, creditcard, options = {})
        post = ''
        add_preamble(post, :reverse)
        add_amount(post, money)
        post << Time.now.strftime('%m%d%y%H%M')
        post << fixed_len(options, :stan, 6)
        post << fixed_len(options, :date, 6)
        post << fixed_len(options, :time, 6)
        post << fixed_len(options, :pos_entry_mode, 3)
        post << fixed_len(options, :pos_condition_code, 10)
        post << fixed_len(@options, :bid, 4)
        post << fixed_len(@options, :tid, 3)
        post << fixed_len(@options, :mid, 12)
        post << fixed_len(options, :lane_id, 3)
        add_creditcard(post, creditcard, options)
        post << fixed_len(options, :additional_data, 8)
        post << fixed_len(options, :clerk, 8)
        post << '000' # network management code
        post << fixed_len(options, :original_rrn, 9)
        post << fixed_len(options, :input_capability, 2)
        post << fixed_len(options, :reverse_amount, 9)
        post << fixed_len(options, :trace, 16, ' ')
        post << self.RS
        add_group(post, 1, options[:order_id])
        add_g2(post, options)
        add_group(post, 3, options[:avv])
        add_group(post, 9, options[:processing_indicators])
        add_group(post, 14, options[:original_rrn])
        add_g28(post, creditcard, options)
        add_group(post, 45, options[:user_data_1])
        add_g58(post, options[:shipping_address], options) unless options[:shipping_address].nil?
        add_g60(post, options) unless options[:ip].nil?

        commit(post)
      end

      def void(authorization, options = {})
        raise ArgumentError, 'Missing required parameter: authorization' unless authorization.present?

        creditcard = options[:credit_card]
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?

        retrieval_reference, = split_authorization(authorization)

        post = ''
        add_preamble(post, :void)
        if options[:token_id].nil?
          post << creditcard.number.ljust(19, ' ')
        else
          post << ' ' * 19
        end
        post << Time.now.strftime('%m%d%y%H%M')
        post << fixed_len(options, :stan, 6)
        post << fixed_len(options, :date, 6)
        post << fixed_len(options, :time, 6)
        post << fixed_len(@options, :bid, 4)
        post << fixed_len(@options, :tid, 3)
        post << fixed_len(@options, :mid, 12)
        post << fixed_len(options, :lane_id, 3)
        post << fixed_len(options, :additional_data, 8)
        post << fixed_len(options, :clerk, 8)
        post << '000' # network management code
        post << retrieval_reference.to_s.rjust(8, '0')
        post << fixed_len(options, :input_capability, 2)
        post << fixed_len(options, :trace, 16, ' ')
        post << self.RS
        add_group(post, 9, options[:processing_indicators])
        add_group(post, 14, options[:original_rrn])
        add_g28(post, creditcard, options)
        add_group(post, 45, options[:user_data_1])
        add_g48(post, options) unless options[:api_transaction_id].nil?

        commit(post)
      end

      def refund(money, authorization, options = {})
        creditcard = options[:credit_card]
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?

        commit_auth_or_sale(money, creditcard, :refund, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(Authorization: Basic [^\s]+), 'Authorization: Basic [FILTERED]').
          gsub(%r(REQUEST=[^\s]*)m, 'REQUEST=[FILTERED]')
      end

      private

      def fixed_len(options, key, len, pad = '0')
        formatted_value = options[key].to_s.rjust(len, pad)
        raise ArgumentError, "Parameter value too long: #{key}" if formatted_value.length > len

        formatted_value
      end

      def commit_auth_or_sale(money, creditcard, action, options = {})
        post = ''
        add_preamble(post, action)
        add_amount(post, money)
        post << Time.now.strftime('%m%d%y%H%M')
        post << fixed_len(options, :stan, 6)
        post << fixed_len(options, :date, 6)
        post << fixed_len(options, :time, 6)
        post << fixed_len(options, :pos_entry_mode, 3)
        post << fixed_len(options, :pos_condition_code, 10)
        post << fixed_len(@options, :bid, 4)
        post << fixed_len(@options, :tid, 3)
        post << fixed_len(@options, :mid, 12)
        post << fixed_len(options, :lane_id, 3)
        add_creditcard(post, creditcard, options)
        post << fixed_len(options, :additional_data, 8)
        post << fixed_len(options, :clerk, 8)
        post << '0' * 9 # cash back
        if [:purchase, :purchase_avs, :refund].include?(action)
          post << '00' # extended payment code
        end
        post << '000' # network management code
        add_avs(post, options) unless options[:billing_address].nil? || action == :refund
        post << fixed_len(options, :input_capability, 2)
        post << fixed_len(options, :customer, 20, ' ')
        post << fixed_len(options, :tax, 9)
        post << fixed_len(options, :trace, 16, ' ')
        post << self.RS
        add_group(post, 1, options[:order_id])
        add_g2(post, options)
        add_group(post, 3, options[:avv])
        add_group(post, 8, options[:pos_data_code])
        add_group(post, 9, options[:processing_indicators])
        add_g28(post, creditcard, options)

        if [:authorize, :authorize_avs, :purchase, :purchase_avs].include?(action)
          add_g42(post, options) unless options[:merchant_name].nil? || options[:merchant_city].nil? || options[:merchant_state].nil?
          add_g57(post, options[:billing_address], options) unless options[:billing_address].nil?
          add_g59(post, options[:billing_address], options)
        end

        if [:authorize, :authorize_avs, :refund, :purchase, :purchase_avs].include?(action)
          add_g58(post, options[:shipping_address], options) unless options[:shipping_address].nil?
          add_g60(post, options) unless options[:ip].nil?
        end

        add_group(post, 45, options[:user_data_1])

        commit(post)
      end

      def commit_token_conversion(creditcard, options = {})
        post = ''
        add_preamble(post, :token_convert)
        post << Time.now.strftime('%m%d%y%H%M')
        post << fixed_len(options, :stan, 6)
        post << fixed_len(options, :date, 6)
        post << fixed_len(options, :time, 6)
        post << fixed_len(options, :pos_entry_mode, 3)
        post << fixed_len(options, :pos_condition_code, 10)
        post << fixed_len(@options, :bid, 4)
        post << fixed_len(@options, :tid, 3)
        post << fixed_len(@options, :mid, 12)
        post << fixed_len(options, :lane_id, 3)
        add_creditcard(post, creditcard, options)
        post << fixed_len(options, :additional_data, 8)
        post << fixed_len(options, :clerk, 8)
        post << '000' # network management code
        post << fixed_len(options, :input_capability, 2)
        post << fixed_len(options, :trace, 16, ' ')
        post << fixed_len(options, :token_date, 8, '9')
        post << fixed_len(options, :token_time, 6, '9')
        post << self.RS
        add_group(post, 1, options[:order_id])
        add_g2(post, options)
        add_group(post, 3, options[:avv])
        add_group(post, 8, options[:pos_data_code])
        add_group(post, 9, options[:processing_indicators])
        add_g28(post, creditcard, options)
        add_group(post, 45, options[:user_data_1])

        commit(post)
      end

      def add_preamble(post, action)
        post << 'I2.'
        post << fixed_len(@options, :network, 6)
        post << self.actions[action]
      end

      def add_amount(post, money)
        post << amount(money).to_s.rjust(9, '0')
      end

      def add_creditcard(post, creditcard, options)
        extra = ''
        cc = ''

        if options[:token_id].nil?
          cc << creditcard.number
          if !creditcard.month.nil? && !creditcard.year.nil?
            extra << expdate(creditcard)
          end
          if creditcard.verification_value?
            extra << creditcard.verification_value
          end

          if extra.length > 0
            cc << '='
            cc << extra
          end
        end
        post << cc.rjust(76, ' ')
      end

      def expdate(creditcard)
        "#{format(creditcard.year, :two_digits)}#{format(creditcard.month, :two_digits)}"
      end

      def add_avs(post, options)
        if (address = options[:billing_address])
          post << address[:address1].to_s[0, 20].ljust(20, ' ')
          post << address[:zip].to_s[0, 9].ljust(9, ' ')
        else
          post << ' ' * 29
        end
      end

      def add_group(post, num, value)
        return if value.nil?

        post << 'G'
        post << num.to_s.rjust(3, '0')
        post << value.to_s
        post << self.GS
      end

      def add_g2(post, options)
        return if options[:cavv].nil?

        post << 'G002'
        post << fixed_len(options, :xid, 40, ' ')
        post << fixed_len(options, :cavv, 40, ' ')
        post << options[:eci]
        post << self.GS
      end

      def add_g28(post, creditcard, options)
        return if options[:token_id].nil?

        post << 'G028'
        post << creditcard.number.to_s.rjust(19, ' ')
        post << fixed_len(options, :token_id, 6, ' ')
        extra = ''
        if !creditcard.month.nil? && !creditcard.year.nil?
          extra << "#{format(creditcard.month, :two_digits)}#{format(creditcard.year, :two_digits)}"
        end
        if creditcard.verification_value?
          extra << creditcard.verification_value.to_s.rjust(4, ' ')
        end
        post << extra
        post << self.GS
      end

      def add_g42(post, options)
        post << 'G042'
        post << options[:merchant_name].ljust(25, ' ')
        post << options[:merchant_city].ljust(13, ' ')
        post << options[:merchant_state].ljust(2, ' ')
        post << self.GS
      end

      def add_g48(post, options)
        post << 'G048'
        post << 'GU'
        post << options[:api_transaction_id].length.to_s.rjust(3, '0')
        post << options[:api_transaction_id]
        post << self.GS
      end

      def add_g57(post, billing_address, _options)
        post << 'G057'
        post << (billing_address[:address1] || '').ljust(40, ' ')
        post << (billing_address[:address2] || '').ljust(40, ' ')
        post << (billing_address[:city] || '').ljust(18, ' ')
        post << (billing_address[:zip] || '').ljust(9, ' ')
        post << (billing_address[:state] || '').ljust(2, ' ')
        post << (billing_address[:country] || '').ljust(3, ' ')
        post << self.GS
      end

      def add_g58(post, shipping_address, _options)
        post << 'G058'
        post << (shipping_address[:address1] || '').ljust(40, ' ')
        post << (shipping_address[:address2] || '').ljust(40, ' ')
        post << (shipping_address[:city] || '').ljust(18, ' ')
        post << (shipping_address[:zip] || '').ljust(9, ' ')
        post << (shipping_address[:state] || '').ljust(2, ' ')
        post << (shipping_address[:country] || '').ljust(3, ' ')
        post << self.GS
      end

      def add_g59(post, billing_address, options)
        post << 'G059'
        post << (options[:customer_id] || '').ljust(50, ' ')
        post << (options[:order_id] || '').ljust(32, ' ')

        if billing_address.nil?
          post << ''.ljust(64, ' ')
        else
          post << (billing_address[:email] || '').ljust(64, ' ')
        end

        if billing_address.nil?
          post << ''.ljust(10, ' ')
        else
          post << (billing_address[:phone] || '').ljust(10, ' ')
        end

        post << self.GS
      end

      def add_g60(post, options)
        post << 'G060'
        post << format_ip(options[:ip])

        if options[:web_session_id].nil?
          post << ''.ljust(128, ' ')
        else
          post << options[:web_session_id]
        end

        post << self.GS
      end

      def commit(post_data)
        full_post = 'REQUEST='
        full_post << 'BT'
        full_post << post_data.length.to_s.rjust(4, '0')
        full_post << @station_id.to_s.ljust(15, ' ')[0, 15]
        full_post << CGI.escape(post_data)

        raw_response = ssl_post(url, full_post, header_data)
        response = parse(raw_response)

        Response.new(success?(response), message_from(response), response,
          test: test?,
          authorization: authorization_from(response),
          avs_result: { code: response[:avs_response].to_s[1, 1] },
          cvv_result: response[:avs_response].to_s[0, 1])
      end

      def success?(response)
        %w[91 90 53].include?(response[:bit_map])
      end

      def message_from(response)
        if success?(response)
          'Transaction successful'
        else
          response[:error_text].to_s.strip
        end
      end

      def authorization_from(response)
        [
          response[:retrieval_reference],
          response[:authorization],
          response[:avs_response],
          response[:payment_service_indicator],
          response[:transaction_identifier],
          response[:visa_validation_code]
        ].join(';')
      end

      def split_authorization(auth)
        auth.to_s.split(';')
      end

      def url
        test? ? test_url : live_url
      end

      def header_data
        {
          'Authorization' => 'Basic ' + Base64.strict_encode64("#{@options[:login]}:#{@options[:password]}").chomp,
          'Content-Type' => 'application/x-www-form-urlencoded'
        }
      end

      def format_ip(ip)
        parts = ip.split('.')
        parts = parts.map { |part| part.rjust(3, '0') }
        parts.join('.')
      end

      def parse(response)
        parsed = {}

        raise ActiveMerchant::InvalidResponseError, 'Error: No data returned from Vantiv' unless response.length >= 3
        raise ActiveMerchant::InvalidResponseError, "Error: Vantiv returned Host Error Code #{response[0, 3]}" unless response[0, 3] == '000'

        response = response[25..-1]
        parsed[:message_type] = response[0, 4]
        parsed[:bit_map] = response[4, 2]

        if parsed[:bit_map] == '91' || parsed[:bit_map] == '90'
          fixed_fields = self.approved_response_fields_fixed
        elsif parsed[:bit_map] == '99'
          fixed_fields = self.error_response_fields_fixed
        elsif parsed[:bit_map] == '53'
          fixed_fields = self.approved_token_convert_fields_fixed
        else
          parsed[:unparsed_response_from_gateway] = response
          return parsed
        end

        fixed_fields.each do |param|
          parsed[param[0]] = response[param[1], param[2]]
        end

        group_data = response.split(self.RS)[1]

        unless group_data.nil?
          group_data.split(self.GS).each do |token|
            parsed[token[0, 4].to_sym] = token[4..-1]
          end
        end

        parsed
      end
    end
  end
end
