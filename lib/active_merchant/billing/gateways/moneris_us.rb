require 'rexml/document'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    # To learn more about the Moneris (US) gateway, please contact
    # ussales@moneris.com for a copy of their integration guide.
    class MonerisUsGateway < Gateway
      self.test_url = 'https://esplusqa.moneris.com/gateway_us/servlet/MpgRequest'
      self.live_url = 'https://esplus.moneris.com/gateway_us/servlet/MpgRequest'

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :discover]
      self.homepage_url = 'http://www.monerisusa.com/'
      self.display_name = 'Moneris (US)'

      def initialize(options = {})
        requires!(options, :login, :password)
        @cvv_enabled = options[:cvv_enabled]
        @avs_enabled = options[:avs_enabled]
        options = { crypt_type: 7 }.merge(options)
        super
      end

      def verify(payment_source, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, payment_source, options) }
          r.process(:ignore_result) { capture(0, r.authorization) }
        end
      end

      def authorize(money, payment_source, options = {})
        raise ArgumentError, 'Moneris US gateway does not support ACH authorizations. Use the purchase method for ACH sale transactions.' if card_brand(payment_source) == 'check'

        requires!(options, :order_id)
        post = {}
        add_payment_source(post, payment_source, options)
        post[:amount]     = amount(money)
        post[:order_id]   = options[:order_id]
        post[:address]    = options[:billing_address] || options[:address]
        post[:cavv]       = options[:cavv]
        post[:crypt_type] = options[:crypt_type] || @options[:crypt_type]
        action = (post[:data_key].blank?) ? 'us_preauth' : 'us_res_preauth_cc'
        action = (options[:cavv].blank?) ? action : 'us_cavv_preauth'

        commit(action, post)
      end

      def purchase(money, payment_source, options = {})
        requires!(options, :order_id)
        post = {}
        add_payment_source(post, payment_source, options)
        post[:amount]     = amount(money)
        post[:order_id]   = options[:order_id]
        post[:address]    = options[:billing_address] || options[:address]
        post[:cavv]       = options[:cavv]
        post[:crypt_type] = options[:crypt_type] || @options[:crypt_type]
        action = (post[:data_key].blank?) ? 'us_purchase' : 'us_res_purchase_cc'
        action = (options[:cavv].blank?) ? action : 'us_cavv_purchase'
        action = (card_brand(payment_source) == 'check') ? 'us_ach_debit' : action

        commit(action, post, payment_source)
      end

      def capture(money, authorization, options = {})
        commit 'us_completion', crediting_params(authorization, comp_amount: amount(money))
      end

      def void(authorization, options = {})
        type = split_authorization(authorization)[2]

        action = 'us_purchasecorrection'
        if !type.nil? && type.to_s.downcase == 'ach'
          action = 'us_ach_reversal'
        end
        commit action, crediting_params(authorization)
      end

      def credit(money, authorization, options = {})
        ActiveMerchant.deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      def refund(money, authorization, options = {})
        if options.include?(:credit_card)
          payment_source = options[:credit_card]
          if card_brand(payment_source) == 'check'
            action = 'us_ach_credit'
          else
            action = 'us_ind_refund'
          end
          requires!(options, :order_id)
          post = {}
          add_payment_source(post, payment_source, options)
          post[:amount]     = amount(money)
          post[:order_id]   = options[:order_id]
          post[:crypt_type] = options[:crypt_type] || @options[:crypt_type]
          commit(action, post, payment_source)
        else
          commit 'us_refund', crediting_params(authorization, amount: amount(money))
        end
      end

      def store(credit_card, options = {})
        post = {}
        post[:pan] = credit_card.number
        post[:expdate] = expdate(credit_card)
        post[:crypt_type] = options[:crypt_type] || @options[:crypt_type]
        commit('us_res_add_cc', post)
      end

      def unstore(data_key, options = {})
        post = {}
        post[:data_key] = data_key
        commit('us_res_delete', post)
      end

      def update(data_key, credit_card, options = {})
        post = {}
        post[:pan] = credit_card.number
        post[:expdate] = expdate(credit_card)
        post[:data_key] = data_key
        post[:crypt_type] = options[:crypt_type] || @options[:crypt_type]
        commit('us_res_update_cc', post)
      end

      def supports_check?
        true
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r(<pan>[^<]*</pan>)i, '<pan>[FILTERED]</pan>').
          gsub(%r(<cvd_value>[^<]*</cvd_value>)i, '<cvd_value>[FILTERED]</cvd_value>').
          gsub(%r(<api_token>[^<]*</api_token>)i, '<api_token>[FILTERED]</api_token>').
          gsub(%r(<account_num>[^<]*</account_num>)i, '<account_num>[FILTERED]</account_num>').
          gsub(%r(<routing_num>[^<]*</routing_num>)i, '<routing_num>[FILTERED]</routing_num>')
      end

      private

      def expdate(creditcard)
        sprintf("%.4i", creditcard.year)[-2..-1] + sprintf("%.2i", creditcard.month)
      end

      def add_payment_source(post, source, options)
        if source.is_a?(String)
          post[:data_key]   = source
          post[:cust_id]    = options[:customer]
        elsif card_brand(source) == 'check'
          post[:cust_id]    = options[:customer]
          post[:dl_num]     = options[:drivers_license_number]
          post[:sec]        = (options[:order_source].blank?) ? 'web' : options[:order_source]
        else
          post[:pan]        = source.number
          post[:expdate]    = expdate(source)
          post[:cvd_value]  = source.verification_value if source.verification_value?
          post[:cust_id]    = options[:customer] || source.name
        end
      end

      def crediting_params(authorization, options = {})
        {
          txn_number: split_authorization(authorization)[0],
          order_id: split_authorization(authorization)[1],
          crypt_type: options[:crypt_type] || @options[:crypt_type]
        }.merge(options)
      end

      def split_authorization(authorization)
        if authorization.nil? || authorization.empty? || authorization !~ /;/
          raise ArgumentError, 'You must include a valid authorization code (e.g. "1234;567")'
        else
          authorization.split(';')
        end
      end

      def commit(action, parameters = {}, payment_source = nil)
        data = post_data(action, parameters, payment_source)
        url = test? ? self.test_url : self.live_url
        raw = ssl_post(url, data)
        response = parse(raw)

        Response.new(successful?(response), message_from(response[:message]), response,
          test: test?,
          avs_result: { code: response[:avs_result_code] },
          cvv_result: response[:cvd_result_code] && response[:cvd_result_code][-1, 1],
          authorization: authorization_from(response, payment_source)
        )
      end

      def authorization_from(response = {}, payment_source = nil)
        res = nil
        if response[:trans_id] && response[:receipt_id]
          res = "#{response[:trans_id]};#{response[:receipt_id]}"
          if !payment_source.nil? && card_brand(payment_source) == 'check'
            res += ';ach'
          end
        end
        res
      end

      def successful?(response)
        response[:response_code] &&
          response[:complete] &&
          (0..49).include?(response[:response_code].to_i)
      end

      def parse(xml)
        response = { message: 'Global Error Receipt', complete: false }
        hashify_xml!(xml, response)
        response
      end

      def hashify_xml!(xml, response)
        xml = REXML::Document.new(xml)
        return if xml.root.nil?
        xml.elements.each('//receipt/*') do |node|
          response[node.name.underscore.to_sym] = normalize(node.text)
        end
      end

      def post_data(action, parameters = {}, payment_source = nil)
        xml   = REXML::Document.new
        root  = xml.add_element('request')
        root.add_element('store_id').text  = options[:login]
        root.add_element('api_token').text = options[:password]
        root.add_element(transaction_element(action, parameters, payment_source))

        xml.to_s
      end

      def transaction_element(action, parameters, payment_source)
        transaction = REXML::Element.new(action)

        actions[action].each do |key|
          case key
          when :avs_info
            transaction.add_element(avs_element(parameters[:address])) if @avs_enabled && parameters[:address]
          when :cvd_info
            transaction.add_element(cvd_element(parameters[:cvd_value])) if @cvv_enabled
          when :ach_info
            transaction.add_element(ach_element(parameters, payment_source))
          else
            transaction.add_element(key.to_s).text = parameters[key] unless parameters[key].blank?
          end
        end

        transaction
      end

      def avs_element(address)
        full_address = "#{address[:address1]} #{address[:address2]}"
        tokens = full_address.split(/\s+/)

        element = REXML::Element.new('avs_info')
        element.add_element('avs_street_number').text = tokens.select { |x| x =~ /\d/ }.join(' ')
        element.add_element('avs_street_name').text = tokens.reject { |x| x =~ /\d/ }.join(' ')
        element.add_element('avs_zipcode').text = address[:zip]
        element
      end

      def cvd_element(cvd_value)
        element = REXML::Element.new('cvd_info')
        if cvd_value
          element.add_element('cvd_indicator').text = '1'
          element.add_element('cvd_value').text = cvd_value
        else
          element.add_element('cvd_indicator').text = '0'
        end
        element
      end

      def ach_element(parameters, payment_source)
        element = REXML::Element.new('ach_info')
        element.add_element('sec').text = parameters[:sec]
        element.add_element('routing_num').text = payment_source.routing_number
        element.add_element('account_num').text = payment_source.account_number
        element.add_element('check_num').text = payment_source.number if payment_source.number
        element.add_element('account_type').text = payment_source.account_type if payment_source.account_type
        element.add_element('dl_num').text = parameters[:dl_num] if parameters[:dl_num]
        element
      end

      def message_from(message)
        return 'Unspecified error' if message.blank?
        message.to_s.gsub(/[^\w]/, ' ').split.join(' ').capitalize
      end

      def actions
        {
          'us_purchase'           => [:order_id, :cust_id, :amount, :pan, :expdate, :crypt_type, :avs_info, :cvd_info],
          'us_preauth'            => [:order_id, :cust_id, :amount, :pan, :expdate, :crypt_type, :avs_info, :cvd_info],
          'us_command'            => [:order_id],
          'us_refund'             => [:order_id, :amount, :txn_number, :crypt_type],
          'us_ind_refund'         => [:order_id, :cust_id, :amount, :pan, :expdate, :crypt_type],
          'us_completion'         => [:order_id, :comp_amount, :txn_number, :crypt_type],
          'us_purchasecorrection' => [:order_id, :txn_number, :crypt_type],
          'us_cavv_purchase'      => [:order_id, :cust_id, :amount, :pan, :expdate, :cavv, :crypt_type, :avs_info, :cvd_info],
          'us_cavv_preauth'       => [:order_id, :cust_id, :amount, :pan, :expdate, :cavv, :crypt_type, :avs_info, :cvd_info],
          'us_transact'           => [:order_id, :cust_id, :amount, :pan, :expdate, :crypt_type],
          'us_Batchcloseall'      => [],
          'us_opentotals'         => [:ecr_number],
          'us_batchclose'         => [:ecr_number],
          'us_res_add_cc'         => [:pan, :expdate, :crypt_type],
          'us_res_delete'         => [:data_key],
          'us_res_update_cc'      => [:data_key, :pan, :expdate, :crypt_type],
          'us_res_purchase_cc'    => [:data_key, :order_id, :cust_id, :amount, :crypt_type],
          'us_res_preauth_cc'     => [:data_key, :order_id, :cust_id, :amount, :crypt_type],
          'us_ach_debit'          => [:order_id, :cust_id, :amount, :ach_info],
          'us_ach_reversal'       => [:order_id, :txn_number],
          'us_ach_credit'         => [:order_id, :cust_id, :amount, :ach_info]
        }
      end
    end
  end
end
