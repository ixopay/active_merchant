require 'test_helper'

class ChaseNetConnectTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = ChaseNetConnectGateway.new(
      login: 'test_user',
      password: 'test_pass',
      mid: '000000000001',
      cid: '0001',
      tid: '001'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345'
    }
  end

  def test_successful_authorize
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      # Preamble: STX(1) + L.(2) + A02000(6) + CID(4) + MID(12) + TID(3) + 1(1) + 000001(6) + F(1) + action(2) = 38 bytes
      assert_equal '02', data[36, 2], 'Action code should be 02 for authorize'
    end.respond_with(successful_authorize_response)

    # Also verify the response object
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_success response
    assert_equal 'APPROVED', response.message.strip
    assert response.test?
  end

  def test_failed_authorize
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'DECLINED', response.message.strip
  end

  def test_successful_purchase
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      assert_equal '01', data[36, 2], 'Action code should be 01 for purchase'
    end.respond_with(successful_purchase_response)

    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'APPROVED', response.message.strip
    assert response.test?
    assert_equal '123456;12345678;01', response.authorization
  end

  def test_successful_capture
    authorization = '123456;12345678;02'
    options_with_card = @options.merge(credit_card: @credit_card)

    stub_comms do
      @gateway.capture(@amount, authorization, options_with_card)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      assert_equal '03', data[36, 2], 'Action code should be 03 for capture'
    end.respond_with(successful_capture_response)

    response = stub_comms do
      @gateway.capture(@amount, authorization, options_with_card)
    end.respond_with(successful_capture_response)

    assert_success response
  end

  def test_capture_requires_credit_card
    authorization = '123456;12345678;02'
    assert_raise(ArgumentError) do
      @gateway.capture(@amount, authorization, @options)
    end
  end

  def test_successful_void
    authorization = '123456;12345678;02'
    options_with_card = @options.merge(credit_card: @credit_card)

    stub_comms do
      @gateway.void(authorization, options_with_card)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      assert_equal '41', data[36, 2], 'Action code should be 41 for void'
    end.respond_with(successful_void_response)

    response = stub_comms do
      @gateway.void(authorization, options_with_card)
    end.respond_with(successful_void_response)

    assert_success response
  end

  def test_void_requires_authorization
    options_with_card = @options.merge(credit_card: @credit_card)
    assert_raise(ArgumentError) do
      @gateway.void(nil, options_with_card)
    end
  end

  def test_void_requires_credit_card
    authorization = '123456;12345678;02'
    assert_raise(ArgumentError) do
      @gateway.void(authorization, @options)
    end
  end

  def test_successful_refund
    authorization = '123456;12345678;01'
    options_with_card = @options.merge(credit_card: @credit_card)

    stub_comms do
      @gateway.refund(@amount, authorization, options_with_card)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      assert_equal '06', data[36, 2], 'Action code should be 06 for refund'
    end.respond_with(successful_refund_response)

    response = stub_comms do
      @gateway.refund(@amount, authorization, options_with_card)
    end.respond_with(successful_refund_response)

    assert_success response
  end

  def test_refund_requires_credit_card
    authorization = '123456;12345678;01'
    assert_raise(ArgumentError) do
      @gateway.refund(@amount, authorization, @options)
    end
  end

  def test_reverse_advice
    authorization = '123456;12345678;01'

    stub_comms do
      @gateway.reverse(@amount, authorization, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      assert_equal '46', data[36, 2], 'Action code should be 46 for reverse_advice'
    end.respond_with(successful_reverse_response)

    response = stub_comms do
      @gateway.reverse(@amount, authorization, @credit_card, @options)
    end.respond_with(successful_reverse_response)

    assert_success response
  end

  def test_partial_auth_reverse
    authorization = '123456;12345678;01'
    options_with_partial = @options.merge(partial_auth_reverse: '1')

    stub_comms do
      @gateway.reverse(@amount, authorization, @credit_card, options_with_partial)
    end.check_request do |_endpoint, data, _headers|
      assert data.start_with?("\x02"), 'Request should start with STX'
      assert data.end_with?("\x03"), 'Request should end with ETX'
      assert_equal '09', data[36, 2], 'Action code should be 09 for partial_auth_reverse'
    end.respond_with(successful_partial_reverse_response)

    response = stub_comms do
      @gateway.reverse(@amount, authorization, @credit_card, options_with_partial)
    end.respond_with(successful_partial_reverse_response)

    assert_success response
  end

  def test_preamble_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      # STX (1 byte) = \x02
      assert_equal "\x02", data[0], 'First byte should be STX'
      # L. (2 bytes) - host capture
      assert_equal 'L.', data[1, 2], 'Bytes 1-2 should be L.'
      # A02000 (6 bytes) - routing indicator
      assert_equal 'A02000', data[3, 6], 'Bytes 3-8 should be A02000'
      # CID (4 bytes, right-justified, zero-padded)
      assert_equal '0001', data[9, 4], 'Bytes 9-12 should be CID 0001'
      # MID (12 bytes, right-justified, zero-padded)
      assert_equal '000000000001', data[13, 12], 'Bytes 13-24 should be MID 000000000001'
      # TID (3 bytes, right-justified, zero-padded)
      assert_equal '001', data[25, 3], 'Bytes 25-27 should be TID 001'
      # Single transaction indicator
      assert_equal '1', data[28], 'Byte 28 should be 1 (single transaction)'
      # Sequence number (6 bytes)
      assert_equal '000001', data[29, 6], 'Bytes 29-34 should be sequence number 000001'
      # Transaction class
      assert_equal 'F', data[35], 'Byte 35 should be F (transaction class)'
      # Action code for purchase
      assert_equal '01', data[36, 2], 'Bytes 36-37 should be action code 01 for purchase'
    end.respond_with(successful_purchase_response)
  end

  def test_cvv_token_handling
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      # The CVV token should contain CV, PI, presence indicator, VF, length, and the value
      # Credit card has verification_value '123' by default
      assert_match(/CVPI1VF3123/, data, 'Request should contain CVV token with CV, PI, 1 (present), VF, length 3, and value 123')
    end.respond_with(successful_purchase_response)
  end

  def test_cvv_token_handling_without_cvv
    card_without_cvv = credit_card('4111111111111111', verification_value: '')

    stub_comms do
      @gateway.purchase(@amount, card_without_cvv, @options)
    end.check_request do |_endpoint, data, _headers|
      # When CVV is not present, should send PI9 (not provided)
      assert_match(/CVPI9/, data, 'Request should contain CVV token with PI9 when CVV not present')
      assert_no_match(/VF/, data, 'Request should not contain VF token when CVV not present')
    end.respond_with(successful_purchase_response)
  end

  def test_cavv_visa
    options_with_cavv = @options.merge(cavv: visa_cavv_base64)
    visa_card = credit_card('4111111111111111', brand: 'visa')

    stub_comms do
      @gateway.purchase(@amount, visa_card, options_with_cavv)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/VA/, data, 'Request should contain VA token for Visa CAVV')
      assert_no_match(/SC/, data, 'Request should not contain SC token for Visa CAVV')
    end.respond_with(successful_purchase_response)
  end

  def test_cavv_mastercard
    options_with_cavv = @options.merge(cavv: 'ASNFZ4mrze8BI0VniavN7wAAAAA=')
    mc_card = credit_card('5500000000000004', brand: 'master')

    stub_comms do
      @gateway.purchase(@amount, mc_card, options_with_cavv)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/SC2/, data, 'Request should contain SC2 token for MasterCard CAVV')
      assert_match(/ASNFZ4mrze8BI0VniavN7wAAAAA=/, data, 'Request should contain raw CAVV value for MasterCard')
      assert_no_match(/VA/, data, 'Request should not contain VA token for MasterCard CAVV')
    end.respond_with(successful_purchase_response)
  end

  def test_primary_secondary_failover
    # First call to primary URL raises ConnectionError, triggering failover to secondary
    call_count = 0
    @gateway.stubs(:ssl_post).with { |url, *_args|
      call_count += 1
      if call_count == 1
        assert_match(/var1/, url, 'First call should be to primary URL')
        raise ActiveMerchant::ConnectionError.new('Connection refused', RuntimeError.new('Connection refused'))
      else
        assert_match(/var2/, url, 'Second call should be to secondary URL')
        true
      end
    }.returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 2, call_count, 'Should have made 2 ssl_post calls (primary + secondary)'
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = "Auth-User: test_user\nAuth-Password: test_pass\n\x02L.A02000some_binary_data\x03"
    scrubbed = @gateway.scrub(transcript)

    assert_equal 'Auth-User: [FILTERED]', scrubbed.lines.first.strip
    assert_match(/Auth-Password: \[FILTERED\]/, scrubbed)
    assert_match(/\[FILTERED_BINARY_DATA\]/, scrubbed)
    assert_no_match(/test_user/, scrubbed)
    assert_no_match(/test_pass/, scrubbed)
    assert_no_match(/\x02/, scrubbed)
    assert_no_match(/\x03/, scrubbed)
  end

  def test_successful_purchase_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'APPROVED', response.message.strip
    assert_equal '123456;12345678;01', response.authorization
    assert response.test?
  end

  def test_failed_purchase_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'DECLINED', response.message.strip
    assert_equal Gateway::STANDARD_ERROR_CODE[:processing_error], response.error_code
  end

  def test_avs_result_returned
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'Y', response.avs_result['code']
  end

  def test_cvv_result_returned
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal '12M', response.cvv_result['code']
  end

  def test_authorization_format
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    # Authorization should be "response_code;reference_number;action_code"
    auth = response.authorization
    parts = auth.split(';')
    assert_equal 3, parts.length, 'Authorization should have 3 parts separated by semicolons'
    assert_equal '123456', parts[0], 'First part should be response_code'
    assert_equal '12345678', parts[1], 'Second part should be reference_number'
    assert_equal '01', parts[2], 'Third part should be action code for purchase'
  end

  def test_header_data_includes_credentials
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, _data, headers|
      assert_equal '000000000001', headers['Auth-MID']
      assert_equal 'test_user', headers['Auth-User']
      assert_equal 'test_pass', headers['Auth-Password']
      assert_equal 'false', headers['Header-Record']
      assert_equal 'true', headers['Stateless-Transaction']
      assert_equal 'UTF197/HCS', headers['Content-Type']
      assert_equal '001', headers['Auth-TID']
    end.respond_with(successful_purchase_response)
  end

  private

  # Valid base64-encoded CAVV that decodes to a 20-byte value (40 hex chars)
  def visa_cavv_base64
    # 20 bytes of data, base64 encoded
    ['0123456789abcdef01234567890abcdef0123456'].pack('H*').then { |raw| [raw].pack('m0') }
  end

  # Build a response with STX framing and FS-delimited fields
  # Fixed data structure (62 chars total):
  #   action_code(1) + avs_performed(1) + response_code(6) + batch_number(6) +
  #   reference_number(8) + sequence_number(6) + message(32) + card_type(2)
  def build_response(action_code:, avs: 'Y', response_code: '123456', batch: '000001',
                     ref_num: '12345678', seq: '000001', message: 'APPROVED', card_type: 'VI',
                     tokens: 'CV12M')
    fixed = action_code.to_s +
            avs.to_s +
            response_code.to_s.ljust(6, '0') +
            batch.to_s.ljust(6, '0') +
            ref_num.to_s.ljust(8, '0') +
            seq.to_s.ljust(6, '0') +
            message.to_s.ljust(32, ' ') +
            card_type.to_s.ljust(2, ' ')

    fs = "\x1C"
    # Fields: fixed_data[0], interchange[1], auth_network_source[2], (empty)[3],
    #         optional_data[4], (empty)[5..9], tokens[10+]
    response_body = fixed +
                    fs + 'interchange' +
                    fs + 'auth_source' +
                    fs +
                    fs + 'optional' +
                    fs +
                    fs +
                    fs +
                    fs +
                    fs +
                    fs + tokens

    "\x02#{response_body}\x03"
  end

  def successful_purchase_response
    build_response(action_code: 'A', message: 'APPROVED', card_type: 'VI')
  end

  def successful_authorize_response
    build_response(action_code: 'A', message: 'APPROVED', card_type: 'VI')
  end

  def failed_purchase_response
    build_response(action_code: 'D', avs: 'N', response_code: '654321',
                   message: 'DECLINED', card_type: 'VI')
  end

  def successful_capture_response
    build_response(action_code: 'A', message: 'CAPTURED', card_type: 'VI')
  end

  def successful_void_response
    build_response(action_code: 'A', message: 'VOIDED', card_type: 'VI')
  end

  def successful_refund_response
    build_response(action_code: 'A', message: 'REFUNDED', card_type: 'VI')
  end

  def successful_reverse_response
    build_response(action_code: 'A', message: 'REVERSED', card_type: 'VI')
  end

  def successful_partial_reverse_response
    build_response(action_code: 'A', message: 'PARTIAL REVERSED', card_type: 'VI')
  end
end
