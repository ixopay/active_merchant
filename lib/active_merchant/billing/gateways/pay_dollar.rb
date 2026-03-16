module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayDollarGateway < Gateway
      self.test_url = 'https://test.paydollar.com/b2cDemo/eng/directPay/payComp.jsp'
      self.live_url = 'https://www.paydollar.com/b2c2/eng/directPay/payComp.jsp'

      self.default_currency = '702'
      self.money_format = :dollars
      self.currencies_without_fractions = %w(392 704 901 360)
      self.supported_countries = ['HK', 'SG', 'MY']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :jcb]

      self.homepage_url = 'http://www.paydollar.com'
      self.display_name = 'PayDollar'

      TRANSACTIONS = {
        purchase: 'N',
        authorization: 'H'
      }

      def initialize(options = {})
        requires!(options, :merchant_id)
        super
      end

      def purchase(amount, payment, options = {})
        auth_or_purchase(:purchase, amount, payment, options)
      end

      def authorize(amount, payment, options = {})
        auth_or_purchase(:authorization, amount, payment, options)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((cardNo=)[^&]*)i, '\1[FILTERED]').
          gsub(%r((securityCode=)[^&]*)i, '\1[FILTERED]')
      end

      private

      def auth_or_purchase(transaction_type, amount, payment, options)
        requires!(options, :order_id)
        post = PostData.new
        post[:orderRef] = truncate(options[:order_id], 35)
        add_amount(post, amount, options)
        post[:lang] = 'E'
        post[:merchantId] = @options[:merchant_id]
        add_payment(post, payment, options)
        post[:payType] = TRANSACTIONS[transaction_type]
        add_address(post, options)
        post[:remark] = options[:description] unless options[:description].blank?

        commit(post)
      end

      def add_amount(post, amount, options)
        new_currency_code = currency_code(options[:currency] || self.default_currency)

        post[:currCode] = new_currency_code
        post[:amount] = localized_amount(amount, new_currency_code)
      end

      def currency_code(currency)
        # PayDollar uses numeric ISO 4217 currency codes (e.g. '702' for SGD)
        currency.to_s
      end

      def add_payment(post, creditcard, options)
        raise ArgumentError, 'Missing required parameter: credit_card' if creditcard.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:number' if creditcard.number.blank?
        raise ArgumentError, 'Missing required parameter: credit_card:month' if creditcard.month.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:year' if creditcard.year.nil?
        raise ArgumentError, 'Missing required parameter: credit_card:verification_value' unless creditcard.verification_value

        post[:pMethod] = format_brand(creditcard.brand)
        post[:epMonth] = format(creditcard.month, :two_digits)
        post[:epYear] = format(creditcard.year, :four_digits)
        post[:cardNo] = creditcard.number
        post[:cardHolder] = creditcard.name if creditcard.name?
        post[:securityCode] = creditcard.verification_value
      end

      def add_address(post, options)
        if billing_address = options[:billing_address] || options[:address]
          post[:billingFirstName]  = billing_address[:first_name]
          post[:billingLastName]   = billing_address[:last_name]
          post[:billingStreet1]    = billing_address[:address1]
          post[:billingStreet2]    = billing_address[:address2]
          post[:billingCity]       = billing_address[:city]
          post[:billingState]      = billing_address[:state]
          post[:billingPostalCode] = billing_address[:zip]
          post[:billingCountry]    = billing_address[:country]
        end
        post[:billingEmail]      = options[:email] unless options[:email].blank?
        post[:custIPAddress]     = options[:ip] unless options[:ip].blank?
      end

      def commit(post)
        url = test? ? self.test_url : self.live_url
        response = parse(ssl_post(url, post.to_post_data))

        Response.new(success?(response), message_from(response), response,
          test: test?,
          authorization: response[:AuthId]
        )
      end

      def parse(body)
        Hash[CGI::parse(body).map { |k, v| [k.intern, v.first] }]
      end

      def success?(response)
        response[:successcode] == '0'
      end

      def message_from(response)
        response[:errMsg]
      end

      def format_brand(brand)
        case brand
        when 'visa' then 'VISA'
        when 'master' then 'Master'
        when 'diners_club' then 'Diners'
        when 'american_express' then 'AMEX'
        when 'jcb' then 'JCB'
        else
          brand
        end
      end
    end
  end
end
