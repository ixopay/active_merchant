require 'test_helper'

class VantivOnlineSystemsTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = VantivOnlineSystemsGateway.new(
      login: 'test_user',
      password: 'test_pass',
      mid: '000000000001',
      bid: '0001',
      tid: '001',
      network: '000000'
    )

    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = { order_id: '12345' }
  end

  def test_successful_authorize
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000010021004000/, data)
    end.respond_with(successful_authorize_response)

    assert_success response
    assert_equal 'Transaction successful', response.message
  end

  def test_authorize_with_avs
    options = @options.merge(billing_address: address)

    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000010025524000/, data)
    end.respond_with(successful_authorize_response)

    assert_success response
  end

  def test_failed_authorize
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'DECLINED', response.message.strip
  end

  def test_successful_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000020022004000/, data)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'Transaction successful', response.message
  end

  def test_purchase_with_avs
    options = @options.merge(billing_address: address)

    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000020025524000/, data)
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_successful_capture
    authorization = '12345678;ABC123;YY;1;000000000000000;0000'
    options = @options.merge(credit_card: @credit_card)

    response = stub_comms do
      @gateway.capture(@amount, authorization, options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000022024004000/, data)
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_capture_requires_credit_card
    authorization = '12345678;ABC123;YY;1;000000000000000;0000'

    assert_raises(ArgumentError) do
      @gateway.capture(@amount, authorization, @options)
    end
  end

  def test_capture_requires_authorization
    options = @options.merge(credit_card: @credit_card)

    assert_raises(ArgumentError) do
      @gateway.capture(@amount, nil, options)
    end
  end

  def test_successful_void
    authorization = '12345678;ABC123;YY;1;000000000000000;0000'
    options = @options.merge(credit_card: @credit_card)

    response = stub_comms do
      @gateway.void(authorization, options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000040001/, data)
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_void_requires_credit_card
    authorization = '12345678;ABC123;YY;1;000000000000000;0000'

    assert_raises(ArgumentError) do
      @gateway.void(authorization, @options)
    end
  end

  def test_successful_refund
    authorization = '12345678;ABC123;YY;1;000000000000000;0000'
    options = @options.merge(credit_card: @credit_card)

    response = stub_comms do
      @gateway.refund(@amount, authorization, options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000020022204000/, data)
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_refund_requires_credit_card
    authorization = '12345678;ABC123;YY;1;000000000000000;0000'

    assert_raises(ArgumentError) do
      @gateway.refund(@amount, authorization, @options)
    end
  end

  def test_successful_reverse
    response = stub_comms do
      @gateway.reverse(@amount, 'AUTH123', @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000010009224000/, data)
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_token_convert
    options = @options.merge(authorization_type: 'token_convert')

    response = stub_comms do
      @gateway.authorize(nil, @credit_card, options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/I2\.000000010050800000/, data)
    end.respond_with(successful_token_convert_response)

    assert_success response
  end

  def test_preamble_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      # The post data starts with REQUEST=BT followed by length and station_id,
      # then the CGI-escaped message body. Decode to check preamble structure.
      raw = data.sub(/^REQUEST=BT\d{4}.{15}/, '')
      decoded = CGI.unescape(raw)
      assert decoded.start_with?('I2.'), "Expected preamble to start with 'I2.', got: #{decoded[0, 10]}"
      # After 'I2.' should be the 6-char network code
      assert_equal '000000', decoded[3, 6]
      # After network should be the 12-char action code for purchase
      assert_equal '020022004000', decoded[9, 12]
    end.respond_with(successful_purchase_response)
  end

  def test_amount_formatting
    stub_comms do
      @gateway.purchase(100, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      raw = data.sub(/^REQUEST=BT\d{4}.{15}/, '')
      decoded = CGI.unescape(raw)
      # After preamble (3 + 6 + 12 = 21 chars), the 9-char amount field
      amount_field = decoded[21, 9]
      assert_equal '000000100', amount_field, "Expected amount 100 to be right-justified in 9 chars with leading zeros"
    end.respond_with(successful_purchase_response)
  end

  def test_amount_formatting_large_amount
    stub_comms do
      @gateway.purchase(99999, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      raw = data.sub(/^REQUEST=BT\d{4}.{15}/, '')
      decoded = CGI.unescape(raw)
      amount_field = decoded[21, 9]
      assert_equal '000099999', amount_field, "Expected amount 99999 to be right-justified in 9 chars with leading zeros"
    end.respond_with(successful_purchase_response)
  end

  def test_group_encoding
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      raw = data.sub(/^REQUEST=BT\d{4}.{15}/, '')
      decoded = CGI.unescape(raw)
      # After the RS separator, group data should be present
      parts = decoded.split("\x1E")
      if parts.length > 1
        group_section = parts[1]
        # The order_id group is G001 followed by value and GS separator
        assert_match(/G00112345\x1D/, group_section, "Expected G001 group with order_id value and GS separator")
      end
    end.respond_with(successful_purchase_response)
  end

  def test_bitmap_91_success
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(bitmap_91_response)

    assert_success response
    assert_equal 'Transaction successful', response.message
  end

  def test_bitmap_90_success
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(bitmap_90_response)

    assert_success response
    assert_equal 'Transaction successful', response.message
  end

  def test_bitmap_53_success
    options = @options.merge(authorization_type: 'token_convert')

    response = stub_comms do
      @gateway.authorize(nil, @credit_card, options)
    end.respond_with(successful_token_convert_response)

    assert_success response
    assert_equal 'Transaction successful', response.message
  end

  def test_bitmap_99_error
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'DECLINED', response.message.strip
  end

  def test_station_id_configurable
    custom_station = '123456789012345'
    gateway = VantivOnlineSystemsGateway.new(
      login: 'test_user',
      password: 'test_pass',
      mid: '000000000001',
      bid: '0001',
      tid: '001',
      network: '000000',
      station_id: custom_station
    )

    stub_comms(gateway) do
      gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      # REQUEST=BT<4-digit-length><15-char station_id><escaped body>
      # Station ID starts at position 14 (after "REQUEST=BT" + 4 digit length)
      after_prefix = data.sub(/^REQUEST=BT\d{4}/, '')
      station_in_request = after_prefix[0, 15]
      assert_equal custom_station, station_in_request, "Expected configurable station_id in request"
    end.respond_with(successful_purchase_response)
  end

  def test_station_id_defaults_to_zeros
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      after_prefix = data.sub(/^REQUEST=BT\d{4}/, '')
      station_in_request = after_prefix[0, 15]
      assert_equal '0' * 15, station_in_request, "Expected default station_id to be 15 zeros"
    end.respond_with(successful_purchase_response)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = 'Authorization: Basic dGVzdF91c2VyOnRlc3RfcGFzcw== REQUEST=BT0200000000000000000I2.00000002002200400000000010012345'
    scrubbed = @gateway.scrub(transcript)

    assert_match(/Authorization: Basic \[FILTERED\]/, scrubbed)
    assert_match(/REQUEST=\[FILTERED\]/, scrubbed)
    refute_match(/dGVzdF91c2VyOnRlc3RfcGFzcw==/, scrubbed)
  end

  def test_authorization_string_format
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    auth = response.authorization
    parts = auth.split(';')
    assert_equal 6, parts.length, "Expected authorization to have 6 semicolon-separated parts"
  end

  def test_avs_result_from_response
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_not_nil response.avs_result
  end

  def test_error_response_includes_response_code
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal '303', response.params['response_code']
  end

  def test_invalid_response_too_short
    assert_raises(ActiveMerchant::InvalidResponseError) do
      stub_comms do
        @gateway.purchase(@amount, @credit_card, @options)
      end.respond_with('AB')
    end
  end

  def test_invalid_response_bad_host_code
    assert_raises(ActiveMerchant::InvalidResponseError) do
      stub_comms do
        @gateway.purchase(@amount, @credit_card, @options)
      end.respond_with('999' + ('0' * 22) + '0210' + '91' + ('0' * 101))
    end
  end

  def test_binary_protocol_prefix
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?('REQUEST=BT'), "Expected request to start with 'REQUEST=BT' binary protocol prefix"
    end.respond_with(successful_purchase_response)
  end

  def test_request_length_field
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      # After REQUEST=BT there should be a 4-digit length field
      length_field = data[10, 4]
      assert_match(/^\d{4}$/, length_field, "Expected 4-digit length field after REQUEST=BT")
    end.respond_with(successful_purchase_response)
  end

  def test_supported_countries
    assert_equal ['US'], VantivOnlineSystemsGateway.supported_countries
  end

  def test_supported_card_types
    assert_include VantivOnlineSystemsGateway.supported_cardtypes, :visa
    assert_include VantivOnlineSystemsGateway.supported_cardtypes, :master
    assert_include VantivOnlineSystemsGateway.supported_cardtypes, :american_express
    assert_include VantivOnlineSystemsGateway.supported_cardtypes, :discover
    assert_include VantivOnlineSystemsGateway.supported_cardtypes, :diners_club
  end

  def test_display_name
    assert_equal 'Vantiv Online Systems (610)', VantivOnlineSystemsGateway.display_name
  end

  def test_header_includes_basic_auth
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, _data, headers|
      assert_not_nil headers['Authorization']
      assert headers['Authorization'].start_with?('Basic ')
      expected_encoded = Base64.strict_encode64('test_user:test_pass')
      assert_equal "Basic #{expected_encoded}", headers['Authorization']
    end.respond_with(successful_purchase_response)
  end

  def test_content_type_header
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, _data, headers|
      assert_equal 'application/x-www-form-urlencoded', headers['Content-Type']
    end.respond_with(successful_purchase_response)
  end

  private

  def successful_purchase_response
    header = '000' + ('0' * 22)
    message_type = '0210'
    bit_map = '91'
    # approved_response_fields_fixed layout:
    # processing_code(6,6), transmission_date_time(12,10), stan(22,6), retrieval_reference(28,8),
    # authorization(36,6), avs_response(42,2), payment_service_indicator(44,1),
    # transaction_identifier(45,15), visa_validation_code(60,4), trace_data(64,16),
    # batch_number(80,6), demo_merchant_flag(86,1), card_type(87,4), working_key(91,16)
    fixed = message_type + bit_map +
            '220000' +          # processing_code
            '0101120000' +      # transmission_date_time
            '000001' +          # stan
            '12345678' +        # retrieval_reference
            'ABC123' +          # authorization
            'YY' +              # avs_response
            '1' +               # payment_service_indicator
            ('0' * 15) +        # transaction_identifier
            '0000' +            # visa_validation_code
            ('0' * 16) +        # trace_data
            '000001' +          # batch_number
            '0' +               # demo_merchant_flag
            'VISA' +            # card_type
            ('0' * 16)          # working_key
    header + fixed
  end

  def successful_authorize_response
    successful_purchase_response
  end

  def failed_purchase_response
    header = '000' + ('0' * 22)
    message_type = '0210'
    bit_map = '99'
    # error_response_fields_fixed layout:
    # stan(6,6), avs_response(12,2), payment_service_indicator(14,1),
    # transaction_identifier(15,15), visa_validation_code(30,4), trace_data(34,16),
    # error_text(50,20), response_code(70,3), working_key(73,16)
    fixed = message_type + bit_map +
            '000001' +          # stan
            'NN' +              # avs_response
            '0' +               # payment_service_indicator
            ('0' * 15) +        # transaction_identifier
            '0000' +            # visa_validation_code
            ('0' * 16) +        # trace_data
            'DECLINED'.ljust(20) + # error_text
            '303' +             # response_code
            ('0' * 16)          # working_key
    header + fixed
  end

  def bitmap_91_response
    successful_purchase_response
  end

  def bitmap_90_response
    header = '000' + ('0' * 22)
    message_type = '0210'
    bit_map = '90'
    # Same layout as bitmap 91 (approved_response_fields_fixed)
    fixed = message_type + bit_map +
            '220000' +
            '0101120000' +
            '000001' +
            '12345678' +
            'DEF456' +
            'YN' +
            '1' +
            ('0' * 15) +
            '0000' +
            ('0' * 16) +
            '000002' +
            '0' +
            'MAST' +
            ('0' * 16)
    header + fixed
  end

  def successful_token_convert_response
    header = '000' + ('0' * 22)
    message_type = '0210'
    bit_map = '53'
    # approved_token_convert_fields_fixed layout:
    # processing_code(6,6), transmission_date_time(12,10), stan(22,6),
    # trace_data(28,16), batch_number(44,6), demo_merchant_flag(50,1)
    fixed = message_type + bit_map +
            '500000' +          # processing_code
            '0101120000' +      # transmission_date_time
            '000001' +          # stan
            ('0' * 16) +        # trace_data
            '000001' +          # batch_number
            '0'                 # demo_merchant_flag
    header + fixed
  end
end
