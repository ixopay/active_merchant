module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class SixGateway < Gateway
      self.test_url = {
        authorize: 'https://web2payuat.3cint.com/mxg/service/_2011_02_v5_1_0/Authorise.asmx/RequestNoCardRead',
        purchase: 'https://web2payuat.3cint.com/mxg/service/_2011_02_v5_1_0/Pay.asmx/RequestNoCardRead',
        capture: 'https://web2payuat.3cint.com/mxg/service/_2011_02_v5_1_0/Capture.asmx/RequestAuthorised'
      }
      self.live_url = {
        authorize: 'https://web2pay.3cint.com/mxg/service/_2011_02_v5_1_0/Authorise.asmx/RequestNoCardRead',
        purchase: 'https://web2pay.3cint.com/mxg/service/_2011_02_v5_1_0/Pay.asmx/RequestNoCardRead',
        capture: 'https://web2pay.3cint.com/mxg/service/_2011_02_v5_1_0/Capture.asmx/RequestAuthorised'
      }

      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.homepage_url = 'http://web2pay.3cint.com/'
      self.display_name = 'Six (Web2Pay)'

      self.default_currency = 'USD'
      self.money_format = :cents

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(money, credit_card, options = {})
        post = {}

        add_amount(post, money, options)
        add_credit_card(post, credit_card)
        add_address(post, options)
        add_card_issue(post, options)
        add_customer_data(post, options)
        add_option_flags(post, options)

        commit(:authorize, post)
      end

      def purchase(money, credit_card, options = {})
        post = {}

        add_amount(post, money, options)
        add_credit_card(post, credit_card)
        add_address(post, options)
        add_card_issue(post, options)
        add_customer_data(post, options)
        add_option_flags(post, options)

        commit(:purchase, post)
      end

      def capture(money, authorization, options = {})
        raise ArgumentError.new('Missing required parameter: authorization') unless authorization.present?

        tx_id, authorisation_code = authorization.to_s.split(';')
        post = { TxID: tx_id, AuthorisationCode: authorisation_code }

        add_amount(post, money, options)
        add_option_flags(post, options)

        commit(:capture, post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((CardNumber=)\d+), '\1[FILTERED]').
          gsub(%r((CardCvv2=)\d+), '\1[FILTERED]').
          gsub(%r((ValidationCode=)[^&]*), '\1[FILTERED]')
      end

      private

      def add_amount(post, money, options)
        post[:Amount] = amount(money)
        post[:Currency] = options[:currency] || currency(money)
      end

      def expdate(credit_card)
        year  = format(credit_card.year, :two_digits)
        month = format(credit_card.month, :two_digits)

        "#{year}#{month}"
      end

      def add_credit_card(post, credit_card)
        post[:CardNumber] = credit_card.number
        post[:CardExpiryYYMM] = expdate(credit_card)
        post[:CardCvv2] = credit_card.verification_value
        post[:CardHolderFirstName] = credit_card.first_name
        post[:CardHolderLastName] = credit_card.last_name
      end

      def add_address(post, options)
        billing_address = options[:billing_address] || options[:address]
        if billing_address
          post[:CardHolderAddress1] = billing_address[:address1]
          post[:CardHolderCity] = billing_address[:city]
          post[:CardHolderState] = billing_address[:state]
          post[:CardHolderPostalCode] = billing_address[:zip].to_s
        end
      end

      def add_card_issue(post, options)
        post[:CardIssueYYMM] = options[:card_issue]
        post[:CardIssueNo] = options[:card_issue_no]
      end

      def add_option_flags(post, options)
        post[:OptionFlags] = options[:option_flags]
      end

      def add_customer_data(post, options)
        post[:MerchantRef] = options[:order_id]
        post[:PaymentOkURL] = options[:url]
        post[:UserData1] = options[:user_data_1]
        post[:UserData2] = options[:user_data_2]
        post[:UserData3] = options[:user_data_3]
        post[:UserData4] = options[:user_data_4]
        post[:UserData5] = options[:user_data_5]
      end

      def post_data(parameters = {})
        parameters[:eMerchantID] = @options[:login]
        parameters[:ValidationCode] = @options[:password]

        parameters.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
      end

      def commit(action, parameters)
        url = test? ? self.test_url[action] : self.live_url[action]
        response = parse(ssl_post(url, post_data(parameters)))

        Response.new(response[:return_code] == '0', response[:return_text], response,
          test: test?,
          authorization: authorization_from(response),
          cvv_result: response[:cvv2_result_code],
          avs_result: { code: response[:avs_result_code] }
        )
      end

      def parse(xml)
        response = {}
        xml = REXML::Document.new(xml)

        if root = REXML::XPath.first(xml, '//Web2PayResult')
          root.elements.to_a.each do |node|
            response[node.name.underscore.to_sym] = (node.text || '').strip
          end
        end

        response
      end

      def authorization_from(response)
        if response[:tx_id] && response[:authorisation_code]
          "#{response[:tx_id]};#{response[:authorisation_code]}"
        else
          ''
        end
      end
    end
  end
end
