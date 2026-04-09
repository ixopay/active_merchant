require 'test_helper'

class RocketgateTest < Test::Unit::TestCase
  def setup
    @gateway = RocketgateGateway.new(
      login: 'test_merchant_id',
      password: 'test_gateway_password'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345',
      customer_id: 'cust_001',
      email: 'test@example.com',
      ip: '127.0.0.1'
    }
  end

  def test_gateway_attributes
    assert_equal 'RocketGate', RocketgateGateway.display_name
    assert_equal :dollars, RocketgateGateway.money_format
    assert_include RocketgateGateway.supported_countries, 'US'
    assert_include RocketgateGateway.supported_cardtypes, :visa
    assert_include RocketgateGateway.supported_cardtypes, :master
    assert_include RocketgateGateway.supported_cardtypes, :american_express
    assert_include RocketgateGateway.supported_cardtypes, :discover
  end

  def test_authorize_creates_request_objects
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformAuthOnly).returns(true)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::TRANSACT_ID, 'guid123')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'guid123', response.authorization
    assert_equal 'Transaction Successful', response.message
  end

  def test_purchase_creates_request_objects
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformPurchase).returns(true)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::TRANSACT_ID, 'guid456')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'guid456', response.authorization
  end

  def test_capture_uses_perform_ticket
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformTicket).returns(true)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::TRANSACT_ID, 'guid789')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.capture(@amount, 'guid789', @options)
    assert_success response
  end

  def test_void_uses_perform_void
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformVoid).returns(true)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::TRANSACT_ID, 'guidvoid')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.void('guidvoid', @options)
    assert_success response
  end

  def test_refund_uses_perform_credit
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformCredit).returns(true)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::TRANSACT_ID, 'guidrefund')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.refund(@amount, 'guidrefund', @options)
    assert_success response
  end

  def test_failed_purchase_response
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformPurchase).returns(false)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '1')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '104')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'The bank has declined the transaction.', response.message
  end

  def test_avs_and_cvv_in_response
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformPurchase).returns(true)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '0')
    mock_response.Set(RocketGate::GatewayResponse::TRANSACT_ID, 'guid_avs')
    mock_response.Set(RocketGate::GatewayResponse::AVS_RESPONSE, 'Y')
    mock_response.Set(RocketGate::GatewayResponse::CVV2_CODE, 'M')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Y', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  def test_card_hash_detection
    # Test that a Base64-encoded card hash (contains = sign) uses CARD_HASH
    hash_value = 'dGVzdGhhc2g='
    hashed_card = stub(number: hash_value, verification_value: '123', month: 9, year: 2028, first_name: 'Test', last_name: 'User')
    request = RocketGate::GatewayRequest.new
    @gateway.send(:add_creditcard, request, hashed_card)
    assert_equal hash_value, request.Get(RocketGate::GatewayRequest::CARD_HASH)
  end

  def test_regular_card_number
    request = RocketGate::GatewayRequest.new
    @gateway.send(:add_creditcard, request, @credit_card)
    assert_equal '4111111111111111', request.Get(RocketGate::GatewayRequest::CARDNO)
    assert_equal '123', request.Get(RocketGate::GatewayRequest::CVV2)
  end

  def test_address_state_only_for_us_ca
    request = RocketGate::GatewayRequest.new
    us_address = { address1: '123 Main', city: 'New York', state: 'NY', zip: '10001', country: 'US' }
    @gateway.send(:add_address, request, us_address)
    assert_equal 'NY', request.Get(RocketGate::GatewayRequest::BILLING_STATE)

    request2 = RocketGate::GatewayRequest.new
    uk_address = { address1: '123 Main', city: 'London', state: 'LN', zip: 'SW1', country: 'UK' }
    @gateway.send(:add_address, request2, uk_address)
    assert_nil request2.Get(RocketGate::GatewayRequest::BILLING_STATE)
  end

  def test_recurring_requires_rebill_frequency
    assert_raise(ArgumentError) do
      @gateway.recurring(@amount, @credit_card, @options)
    end
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '<cardNo>4111111111111111</cardNo><cvv2>123</cvv2><merchantPassword>secret</merchantPassword>'
    scrubbed = @gateway.scrub(transcript)

    assert_match(/<cardNo>\[FILTERED\]/, scrubbed)
    assert_match(/<cvv2>\[FILTERED\]/, scrubbed)
    assert_match(/<merchantPassword>\[FILTERED\]/, scrubbed)
    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/>123</, scrubbed)
    assert_no_match(/>secret</, scrubbed)
  end

  def test_response_code_mapping
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformPurchase).returns(false)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '1')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '403')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Invalid Card Number', response.message
  end

  def test_unknown_response_code
    mock_service = mock('service')
    mock_service.expects(:SetTestMode).with(true)
    mock_service.expects(:PerformPurchase).returns(false)

    mock_response = RocketGate::GatewayResponse.new
    mock_response.Set(RocketGate::GatewayResponse::RESPONSE_CODE, '1')
    mock_response.Set(RocketGate::GatewayResponse::REASON_CODE, '999')

    RocketGate::GatewayService.expects(:new).returns(mock_service)
    RocketGate::GatewayResponse.expects(:new).returns(mock_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'ERROR - 999', response.message
  end
end
