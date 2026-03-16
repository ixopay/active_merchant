module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CobreBemAprovaFacilGateway < Gateway
      self.test_url = 'https://teste.aprovafacil.com/cgi-bin/APFW/'
      self.live_url = 'https://www.aprovafacil.com/cgi-bin/APFW/'
      self.supported_countries = ['BR']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club]
      self.default_currency = 'BRL'
      self.money_format = :cents

      self.homepage_url = 'https://www.cobrebem.com/'
      self.display_name = 'Cobre Bem Aprova Facil'

      OPERATIONS = {
        authorize: 'APC',
        capture: 'CAP',
        cancel: 'CAN'
      }.freeze

      def initialize(options = {})
        requires!(options, :login)
        super
      end

      def authorize(money, payment, options = {})
        commit(:authorize, add_auth_fields(money, payment, options), options)
      end

      def capture(money, authorization, options = {})
        process_capture_refund_void(:capture, authorization, money, options)
      end

      def purchase(money, payment, options = {})
        auth_response = authorize(money, payment, options)

        if !auth_response.authorization.present?
          return auth_response
        end

        order_id, transaction_id = auth_response.authorization.to_s.split(";")
        options[:order_id] = order_id

        capture(money, auth_response.authorization, options)
      end

      def refund(money, authorization, options = {})
        process_capture_refund_void(:cancel, authorization, money, options)
      end

      def void(identification, options = {})
        process_capture_refund_void(:cancel, identification, nil, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((NumeroCartao=)[^&]*), '\1[FILTERED]').
          gsub(%r((CodigoSeguranca=)[^&]*), '\1[FILTERED]')
      end

      private

      def add_auth_fields(money, credit_card, transaction_options = {})
        fields = {
          'NumeroDocumento' => transaction_options[:order_id],
          'ValorDocumento' => amount(money),
          'QuantidadeParcelas' => '1',
          'EnderecoIPComprador' => transaction_options[:ip],
          'NomePortadorCartao' => credit_card.name,
          'NumeroCartao' => credit_card.number,
          'MesValidade' => credit_card.month.to_s.rjust(2, '0'),
          'AnoValidade' => credit_card.year.to_s[2, 2],
          'CodigoSeguranca' => credit_card.verification_value,
          'Bandiera' => card_brand(credit_card).upcase
        }

        fields['Adquirente'] = transaction_options[:processor] if transaction_options[:processor] != nil
        fields['Moeda'] = transaction_options[:currency] if transaction_options[:currency] != nil

        if @options[:avs_enabled] != nil && @options[:avs_enabled] == 'true'
          fields['AVS'] = 'S'
          fields['CPFPortadorCartao'] = transaction_options[:user_data_1] if transaction_options[:user_data_1] != nil
          if transaction_options[:billing_address] != nil
            fields['EnderecoPortadorCartao'] = transaction_options[:billing_address][:address1] if transaction_options[:billing_address][:address1] != nil
            fields['CEPPortadorCartao'] = transaction_options[:billing_address][:zip] if transaction_options[:billing_address][:zip] != nil
          end
        end

        fields
      end

      def add_capture_refund_void_fields(authorization, money)
        order_id, transaction_id = authorization.to_s.split(";")

        fields = {
          'NumeroDocumento' => order_id,
          'Transacto' => transaction_id
        }

        if money != nil && money > 0
          fields['ValorDocumento'] = amount(money)
        end

        fields
      end

      def process_capture_refund_void(action, authorization, money, options = {})
        raise ArgumentError.new("Missing required parameter: authorization") unless authorization.present?
        options[:authorization] = authorization
        commit(action, add_capture_refund_void_fields(authorization, money), options)
      end

      def card_brand(card)
        brand = super
        ({ "master" => "mastercard", "american_express" => "amex", "diners_club" => "diners" }[brand] || brand)
      end

      def url(operation)
        url = test? ? test_url : live_url
        url += @options[:login].downcase
        url += '/'
        url += operation
      end

      def commit(operation, request_params, options)
        response = nil
        begin
          uri = URI(url(OPERATIONS[operation]))
          https = Net::HTTP.new(uri.host, uri.port)
          https.use_ssl = true
          https.verify_mode = OpenSSL::SSL::VERIFY_NONE
          request = Net::HTTP::Post.new(uri)

          request.form_data = request_params

          response = https.start { |r| r.request request }

          parsed_response = parse_response(response.body.to_s)

          if parsed_response[:HTML] != nil
            return Response.new(false, "HTML Error Message Returned. See HTML key below for full details.", parsed_response, test: test?)
          end

          success = determine_success(parsed_response)
          message = parsed_response[:ResultadoSolicitacaoAprovacao]
          if options[:authorization] != nil
            authorization = options[:authorization]
          else
            authorization = success ? [options[:order_id], parsed_response[:Transacao]].compact.join(";") : nil
          end

          return Response.new(success, message, parsed_response,
            test: test?,
            authorization: authorization,
            avs_result: { code: parsed_response[:ResultadoAVS] }
          )
        rescue => details
          return Response.new(false, details.to_s, { response: response.body.to_s })
        end
      end

      def determine_success(parsed_response)
        if parsed_response[:TransacaoAprovada] != nil
          return parsed_response[:TransacaoAprovada].to_s == 'true'
        elsif parsed_response[:ResultadoSolicitacaoConfirmacao] != nil
          return !(parsed_response[:ResultadoSolicitacaoConfirmacao].start_with? 'Erro')
        elsif parsed_response[:ResultadoSolicitacaoCancelamento] != nil
          return !(parsed_response[:ResultadoSolicitacaoCancelamento].start_with? 'Erro')
        else
          return false
        end
      end

      def parse_response(response)
        reply = {}

        if response.start_with?('<html>')
          reply[:HTML] = response
        else
          xml = REXML::Document.new(response)
          root = REXML::XPath.first(xml)
          root.elements.to_a.each do |node|
            parse_element(reply, node)
          end
        end

        reply
      end

      def parse_element(reply, node)
        if node.has_elements?
          node.elements.each { |e| parse_element(reply, e) }
        else
          reply[node.name.to_sym] = node.text
        end
        reply
      end
    end
  end
end
