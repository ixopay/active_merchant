require File.dirname(__FILE__) + '/rocketgate/GatewayService'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class RocketgateGateway < Gateway
      self.money_format = :dollars
      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :jcb, :switch, :solo, :maestro]
      self.homepage_url = 'http://www.rocketgate.com/'
      self.display_name = 'RocketGate'

      RESPONSE_CODES = {
        r0: 'Transaction Successful',
        r100: 'No matching transaction',
        r101: 'A void operation cannot be performed because the original transaction has already been voided, credited, or settled.',
        r102: 'A credit operation cannot be performed because the original transaction has already been voided, credited, or has not been settled.',
        r103: 'A ticket operation cannot be performed because the original auth-only transaction has been voided or ticketed.',
        r104: 'The bank has declined the transaction.',
        r105: 'The bank has declined the transaction because the account is over limit.',
        r106: 'The transaction was declined because the security code (CVV) supplied was invalid.',
        r107: 'The bank has declined the transaction because the card is expired.',
        r108: 'The bank has declined the transaction and has requested that the merchant call.',
        r109: 'The bank has declined the transaction and has requested that the merchant pickup the card.',
        r110: 'The bank has declined the transaction due to excessive use of the card.',
        r111: 'The bank has indicated that the account is invalid.',
        r112: 'The bank has indicated that the account is expired.',
        r113: 'The issuing bank is temporarily unavailable. May be tried again later.',
        r117: 'The transaction was declined because the address could not be verified.',
        r150: 'The transaction was declined because the address could not be verified.',
        r151: 'The transaction was declined because the security code (CVV) supplied was invalid.',
        r152: 'The TICKET request was for an invalid amount. Please verify the TICKET for less then the AUTH_ONLY.',
        r154: 'The transaction was declined because of missing or invalid data.',
        r200: 'Transaction was declined',
        r201: 'Transaction was declined',
        r300: 'A DNS failure has prevented the merchant application from resolving gateway host names.',
        r301: 'The merchant application is unable to connect to an appropriate host.',
        r302: 'Transmit error, no payment has occured.',
        r303: 'A timeout occurred while waiting for a transaction response from the gateway servers.',
        r304: 'An error occurred while reading a transaction response.',
        r305: 'Service Unavailable',
        r307: 'Unexpected/Internal Error',
        r311: 'Bank Communications Error',
        r312: 'Bank Communications Error',
        r313: 'Bank Communications Error',
        r314: 'Bank Communications Error',
        r315: 'Bank Communications Error',
        r400: 'Invalid XML',
        r402: 'Invalid Transaction',
        r403: 'Invalid Card Number',
        r404: 'Invalid Expiration',
        r405: 'Invalid Amount',
        r406: 'Invalid Merchant ID',
        r407: 'Invalid Merchant Account',
        r408: 'The merchant account specified in the request is not setup to accept the card type included in the request.',
        r409: 'No Suitable Account',
        r410: 'Invalid Transact ID',
        r411: 'Invalid Access Code',
        r412: 'Invalid Customer Data Length',
        r413: 'Invalid External Data Length',
        r418: 'The currency requested is not invalid',
        r419: 'The currency requested is not accepted',
        r420: 'Invalid subscription parameters requested',
        r422: 'Invalid Country Code requested',
        r438: 'Invalid Site ID requested',
        r441: 'No Invoice ID specified',
        r443: 'No Customer ID specified',
        r444: 'No Customer Name specified',
        r445: 'No Address specified',
        r446: 'No CVV Security Code specified',
        r448: 'No Active Membership found'
      }.freeze

      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end

      def authorize(money, creditcard, options = {})
        request = RocketGate::GatewayRequest.new
        response = RocketGate::GatewayResponse.new
        service = RocketGate::GatewayService.new
        service.SetTestMode(true) if test?

        add_merchant_data(request, options)
        add_customer_data(request, options)
        add_invoice_data(request, money, options)
        add_creditcard(request, creditcard)
        add_address(request, options[:billing_address])
        add_business_rules_data(request, options)

        service.PerformAuthOnly(request, response)
        create_response(response)
      end

      def purchase(money, creditcard, options = {})
        request = RocketGate::GatewayRequest.new
        response = RocketGate::GatewayResponse.new
        service = RocketGate::GatewayService.new
        service.SetTestMode(true) if test?

        add_merchant_data(request, options)
        add_customer_data(request, options)
        add_invoice_data(request, money, options)
        add_creditcard(request, creditcard)
        add_address(request, options[:billing_address])
        add_business_rules_data(request, options)

        service.PerformPurchase(request, response)
        create_response(response)
      end

      def capture(money, authorization, options = {})
        request = RocketGate::GatewayRequest.new
        response = RocketGate::GatewayResponse.new
        service = RocketGate::GatewayService.new
        service.SetTestMode(true) if test?

        add_merchant_data(request, options)
        add_financial_data(request, money, options)
        request.Set(RocketGate::GatewayRequest::TRANSACT_ID, authorization)

        service.PerformTicket(request, response)
        create_response(response)
      end

      def void(authorization, options = {})
        request = RocketGate::GatewayRequest.new
        response = RocketGate::GatewayResponse.new
        service = RocketGate::GatewayService.new
        service.SetTestMode(true) if test?

        add_merchant_data(request, options)
        request.Set(RocketGate::GatewayRequest::TRANSACT_ID, authorization)
        request.Set(RocketGate::GatewayRequest::IPADDRESS, options[:ip])

        service.PerformVoid(request, response)
        create_response(response)
      end

      def refund(money, authorization, options = {})
        request = RocketGate::GatewayRequest.new
        response = RocketGate::GatewayResponse.new
        service = RocketGate::GatewayService.new
        service.SetTestMode(true) if test?

        add_merchant_data(request, options)
        add_financial_data(request, money, options)
        request.Set(RocketGate::GatewayRequest::TRANSACT_ID, authorization)
        request.Set(RocketGate::GatewayRequest::IPADDRESS, options[:ip])

        service.PerformCredit(request, response)
        create_response(response)
      end

      def recurring(money, creditcard, options = {})
        requires!(options, :rebill_frequency)

        request = RocketGate::GatewayRequest.new
        response = RocketGate::GatewayResponse.new
        service = RocketGate::GatewayService.new
        service.SetTestMode(true) if test?

        add_merchant_data(request, options)
        add_customer_data(request, options)
        add_invoice_data(request, money, options)
        add_recurring_data(request, options)
        add_creditcard(request, creditcard)
        add_address(request, options[:billing_address])
        add_business_rules_data(request, options)

        service.PerformPurchase(request, response)
        create_response(response)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((<cardNo>)[^<]*), '\1[FILTERED]').
          gsub(%r((<cvv2>)[^<]*), '\1[FILTERED]').
          gsub(%r((<merchantPassword>)[^<]*), '\1[FILTERED]')
      end

      private

      def add_merchant_data(request, options)
        request.Set(RocketGate::GatewayRequest::MERCHANT_ID, @options[:login])
        request.Set(RocketGate::GatewayRequest::MERCHANT_PASSWORD, @options[:password])
      end

      def add_customer_data(request, options)
        request.Set(RocketGate::GatewayRequest::MERCHANT_CUSTOMER_ID, options[:customer_id])
        request.Set(RocketGate::GatewayRequest::IPADDRESS, options[:ip])
        request.Set(RocketGate::GatewayRequest::EMAIL, options[:email])
      end

      def add_invoice_data(request, money, options)
        request.Set(RocketGate::GatewayRequest::MERCHANT_INVOICE_ID, options[:order_id])
        request.Set(RocketGate::GatewayRequest::AMOUNT, amount(money))
        request.Set(RocketGate::GatewayRequest::CURRENCY, options[:currency] || currency(money))

        request.Set(RocketGate::GatewayRequest::UDF01, options[:udf01])
        request.Set(RocketGate::GatewayRequest::UDF02, options[:udf02])

        request.Set(RocketGate::GatewayRequest::MERCHANT_ACCOUNT, options[:merchant_account])
        request.Set(RocketGate::GatewayRequest::BILLING_TYPE, options[:billing_type])
        request.Set(RocketGate::GatewayRequest::AFFILIATE, options[:affiliate])
        request.Set(RocketGate::GatewayRequest::MERCHANT_SITE_ID, options[:site_id])
        request.Set(RocketGate::GatewayRequest::MERCHANT_DESCRIPTOR, options[:descriptor])
      end

      def add_financial_data(request, money, options)
        request.Set(RocketGate::GatewayRequest::AMOUNT, amount(money))
        request.Set(RocketGate::GatewayRequest::CURRENCY, options[:currency] || currency(money))
      end

      def add_creditcard(request, creditcard)
        card_no = creditcard.number
        card_no = card_no.strip
        if (card_no.length == 44) || (card_no =~ /[A-Z]/i) || (card_no =~ /\+/) || (card_no =~ /=/)
          request.Set(RocketGate::GatewayRequest::CARD_HASH, creditcard.number)
        else
          request.Set(RocketGate::GatewayRequest::CARDNO, creditcard.number)
          request.Set(RocketGate::GatewayRequest::CVV2, creditcard.verification_value)
          request.Set(RocketGate::GatewayRequest::EXPIRE_MONTH, creditcard.month)
          request.Set(RocketGate::GatewayRequest::EXPIRE_YEAR, creditcard.year)
          request.Set(RocketGate::GatewayRequest::CUSTOMER_FIRSTNAME, creditcard.first_name)
          request.Set(RocketGate::GatewayRequest::CUSTOMER_LASTNAME, creditcard.last_name)
        end
      end

      def add_address(request, address)
        return if address.nil?

        request.Set(RocketGate::GatewayRequest::BILLING_ADDRESS, address[:address1])
        request.Set(RocketGate::GatewayRequest::BILLING_CITY, address[:city])
        request.Set(RocketGate::GatewayRequest::BILLING_ZIPCODE, address[:zip])
        request.Set(RocketGate::GatewayRequest::BILLING_COUNTRY, address[:country])

        if address[:state] =~ /[A-Za-z]{2}/ && address[:country] =~ /^(us|ca)$/i
          request.Set(RocketGate::GatewayRequest::BILLING_STATE, address[:state].upcase)
        end
      end

      def add_business_rules_data(request, options)
        request.Set(RocketGate::GatewayRequest::AVS_CHECK, convert_rule_flag(options[:ignore_avs]))
        request.Set(RocketGate::GatewayRequest::CVV2_CHECK, convert_rule_flag(options[:ignore_cvv]))
        request.Set(RocketGate::GatewayRequest::SCRUB, options[:scrub])
      end

      def convert_rule_flag(value)
        return value if value == 'ignore' || value == 'IGNORE'

        value ? false : true
      end

      def add_recurring_data(request, options)
        request.Set(RocketGate::GatewayRequest::REBILL_FREQUENCY, options[:rebill_frequency])
        request.Set(RocketGate::GatewayRequest::REBILL_AMOUNT, options[:rebill_amount])
        request.Set(RocketGate::GatewayRequest::REBILL_START, options[:rebill_start])
      end

      def create_response(response)
        message = nil
        authorization = nil
        success = false

        reason_code = response.Get(RocketGate::GatewayResponse::REASON_CODE)
        message = RESPONSE_CODES[('r' + reason_code).to_sym] || 'ERROR - ' + reason_code
        response_code = response.Get(RocketGate::GatewayResponse::RESPONSE_CODE)
        if response_code != nil && response_code == '0'
          success = true
          authorization = response.Get(RocketGate::GatewayResponse::TRANSACT_ID)
        end

        avs_response = response.Get(RocketGate::GatewayResponse::AVS_RESPONSE)
        cvv2_response = response.Get(RocketGate::GatewayResponse::CVV2_CODE)
        fraud_response = response.Get(RocketGate::GatewayResponse::SCRUB_RESULTS)

        card_hash = response.Get(RocketGate::GatewayResponse::CARD_HASH)
        Response.new(success, message, { result: response_code, exception: response.Get(RocketGate::GatewayResponse::EXCEPTION), card_hash: card_hash },
          test: test?,
          authorization: authorization,
          avs_result: { code: avs_response },
          cvv_result: cvv2_response,
          fraud_review: fraud_response
        )
      end
    end
  end
end
