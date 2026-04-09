module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CredomaticGateway < Gateway

      self.test_url = '' # There is no Test endpoint
      self.live_url = 'https://paycom.credomatic.com/PayComBackEndWeb/common/requestPaycomService.go'

      self.supported_countries = ['GT', 'HN', 'SV', 'NI', 'CR', 'PA']
      self.supported_cardtypes = [:visa, :master, :american_express]
      self.homepage_url = 'https://www.baccredomatic.com/'
      self.display_name = 'BAC Credomatic'
      self.money_format = :cents

      def initialize(options = {})
        requires!(options, :user, :public_key, :private_key, :test)
        raise ArgumentError.new("BAC Credomatic Gateway is not available in the Test environment.") if options[:test] == true
        super
      end

      def authorize(money, creditcard, options = {})
        requires!(options, :order_id)
        if (@options[:avs_enabled])
          requires!(options, :billing_address)
          requires!(options[:billing_address], :address1, :zip)
        end
        post = create_request(options)
        post[:type] = 'auth'

        add_request_hash(post, options, money, :authorize)
        add_credit_card_data(post, creditcard)
        add_amount(post, money)
        add_order_id(post, options)
        add_processor_id(post, options)

        if (@options[:avs_enabled] == 'true')
          add_avs_data(post, options[:billing_address])
        end

        commit(post, money)
      end

      def capture(money, authorization, options = {})
        requires!(options, :credit_card)
        raise ArgumentError.new("Missing required parameter: authorization") unless authorization.present?

        credit_card = options[:credit_card]
        amt, transaction_id = authorization.to_s.split(";")
        post = create_request(options)
        post[:type] = 'sale'

        add_request_hash(post, options, amt.to_i, :capture)
        add_amount(post, amt.to_i)
        add_transaction_id(post, transaction_id)
        add_processor_id(post, options)
        add_credit_card_number(post, credit_card)

        commit(post, amt)
      end

      def purchase(money, creditcard, options = {})
        requires!(options, :order_id)
        if (@options[:avs_enabled])
          requires!(options, :billing_address)
          requires!(options[:billing_address], :address1, :zip)
        end

        auth = authorize(money, creditcard, options)
        options[:credit_card] = creditcard
        capture(money, auth.authorization, options)
      end

      def void(identification, options = {})
        raise ArgumentError.new("Missing required parameter: authorization") unless identification.present?
        money, transaction_id, options[:order_id] = identification.to_s.split(";")

        post = create_request(options)
        post[:type] = 'void'
        post[:amount] = amount(money.to_i)
        post[:orderid] = options[:order_id]

        add_request_hash(post, options, money.to_i, :void)
        add_transaction_id(post, transaction_id)

        commit(post, money)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((ccnumber=)[^&]*), '\1[FILTERED]').
          gsub(%r((cvv=)[^&]*), '\1[FILTERED]').
          gsub(%r((key_id=)[^&]*), '\1[FILTERED]')
      end

      private

      def commit(post, amount)
        request = post_data(flatten_hash(post))
        raw_response = ssl_post(test? ? self.test_url : self.live_url, request, headers)
        response = parse(raw_response)

        Response.new(
          success_from(response),
          message_from(response),
          response,
          test: test?,
          avs_result: avs_from(response),
          cvv_result: cvv_from(response),
          authorization: "#{amount};#{response['transactionid']};#{post[:orderid]}"
        )

      rescue ResponseError => e
        case e.response.code
        when '401'
          return Response.new(false, 'Invalid credentials', {}, test: test?)
        when '403'
          return Response.new(false, 'Not allowed', {}, test: test?)
        when '422'
          return Response.new(false, 'Unprocessable Entity', {}, test: test?)
        when '500'
          if e.response.body.split(' ')[0] == 'validation'
            return Response.new(false, e.response.body.split(' ', 3)[2], {}, test: test?)
          end
        end
        raise
      end

      def flatten_hash(hash, prefix = nil)
        flat_hash = {}
        hash.each_pair do |key, val|
          conc_key = prefix.nil? ? key : "#{prefix}.#{key}"
          if val.is_a?(Hash)
            flat_hash.merge!(flatten_hash(val, conc_key))
          else
            flat_hash[conc_key] = val
          end
        end
        flat_hash
      end

      def headers
        {
          'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8'
        }
      end

      def parse(response)
        if (response[0] == '?')
          response = response[1..-1]
        end

        Hash[
          response.split('&').map do |x|
            key, val = x.split('=', 2)
            [key.split('.').last, CGI.unescape(val)]
          end
        ]
      end

      def post_data(data)
        data.map do |key, val|
          "#{key}=#{CGI.escape(val.to_s)}"
        end.reduce do |x, y|
          "#{x}&#{y}"
        end
      end

      def create_request(options)
        hash = {}
        hash[:username] = @options[:user]
        hash[:key_id] = @options[:public_key]
        hash[:time] = Time.now.to_i.to_s
        hash[:redirect] = options[:url] if options[:url]
        hash
      end

      def add_request_hash(post, options, money, action)
        if action == :authorize && options[:order_id]
          order_id = options[:order_id]
        else
          order_id = ''
        end

        if amount(money) != 0
          amt = amount(money).to_s
        else
          amt = ''
        end

        # MD5(orderid|amount|time|key)
        md5 = Digest::MD5.new
        md5 << order_id + "|"
        md5 << amt + "|"
        md5 << post[:time] + "|"
        md5 << @options[:private_key].to_s

        post[:hash] = md5.hexdigest
      end

      def add_amount(post, money)
        post[:amount] = amount(money).to_s
      end

      def add_avs_data(post, address)
        post[:avs] = address[:address1]
        post[:avs] << " #{address[:address2]}" if address[:address2]
        post[:avs] << " #{address[:zip]}" if address[:zip]
      end

      def add_credit_card_data(post, creditcard)
        add_credit_card_number(post, creditcard)
        post[:ccexp] = "#{format(creditcard.month, :two_digits) if creditcard.month}#{format(creditcard.year, :two_digits) if creditcard.year}"
        post[:cvv] = creditcard.verification_value if creditcard.verification_value
      end

      def add_credit_card_number(post, creditcard)
        post[:ccnumber] = creditcard.number if creditcard.number
      end

      def add_order_id(post, options)
        post[:orderid] = options[:order_id] if options[:order_id]
      end

      def add_processor_id(post, options)
        post[:processor_id] = options[:processor] if options[:processor]
      end

      def add_transaction_id(post, transaction_id)
        post[:transactionid] = transaction_id
      end

      def avs_from(response)
        response['avsresponse'] == "" ? nil : AVSResult.new(code: response['avsresponse'])
      end

      def cvv_from(response)
        response['cvvresponse'] == "" ? nil : CVVResult.new(response['cvvresponse'])
      end

      def message_from(response)
        return "#{response['response_code']}: #{response['responsetext']}"
      end

      def success_from(response)
        return response['response'].to_s == '1'
      end
    end
  end
end
