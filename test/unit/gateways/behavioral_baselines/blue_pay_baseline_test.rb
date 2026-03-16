require 'test_helper'

class BluePayBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = BluePayGateway.new(
      login: 'X',
      password: 'Y'
    )
    @amount = 100
    @credit_card = credit_card
    @options = { ip: '192.168.0.1' }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TRANS_TYPE=SALE/, data)
      assert_match(/AMOUNT=1\.00/, data)
      assert_match(/PAYMENT_ACCOUNT=4242424242424242/, data)
      assert_match(/CARD_CVV2=123/, data)
      assert_match(/CUSTOMER_IP=192\.168\.0\.1/, data)
      assert_match(/PAYMENT_TYPE=CREDIT/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TRANS_TYPE=AUTH/, data)
      assert_match(/AMOUNT=1\.00/, data)
      assert_match(/PAYMENT_ACCOUNT=4242424242424242/, data)
      assert_match(/NAME1=Longbob/, data)
      assert_match(/NAME2=Longsen/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_capture_request_structure
    stub_comms do
      @gateway.capture(@amount, '100134203758')
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TRANS_TYPE=CAPTURE/, data)
      assert_match(/MASTER_ID=100134203758/, data)
      assert_match(/AMOUNT=1\.00/, data)
    end.respond_with(successful_capture_response)
  end

  def test_refund_request_structure
    stub_comms do
      @gateway.refund(@amount, '100134203758')
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TRANS_TYPE=REFUND/, data)
      assert_match(/MASTER_ID=100134203758/, data)
      assert_match(/AMOUNT=1\.00/, data)
    end.respond_with(successful_refund_response)
  end

  def test_void_request_structure
    stub_comms do
      @gateway.void('100134203758')
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TRANS_TYPE=VOID/, data)
      assert_match(/MASTER_ID=100134203758/, data)
    end.respond_with(successful_void_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal '100134203767', response.authorization
    assert_equal 'This transaction has been approved', response.message
    assert_equal '1', response.params['response_code']
    assert_equal '100134203767', response.params['transaction_id']
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_response)

    assert_failure response
    assert_equal '100000000150', response.authorization
    assert_equal '0', response.params['response_code']
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_authorization_response)

    assert_equal '_', response.avs_result['code']
    assert_equal '_', response.cvv_result['code']
  end

  private

  def successful_purchase_response
    'AUTH_CODE=GYRUY&PAYMENT_ACCOUNT_MASK=xxxxxxxxxxxx4242&CARD_TYPE=VISA&TRANS_TYPE=SALE&REBID=&STATUS=1&AVS=_&TRANS_ID=100134203767&CVV2=_&MESSAGE=Approved%20Sale'
  end

  def successful_authorization_response
    'AUTH_CODE=RSWUC&PAYMENT_ACCOUNT_MASK=xxxxxxxxxxxx4242&CARD_TYPE=VISA&TRANS_TYPE=AUTH&REBID=&STATUS=1&AVS=_&TRANS_ID=100134229528&CVV2=_&MESSAGE=Approved%20Auth'
  end

  def successful_capture_response
    'AUTH_CODE=CHTHX&PAYMENT_ACCOUNT_MASK=xxxxxxxxxxxx4242&CARD_TYPE=VISA&TRANS_TYPE=CAPTURE&REBID=&STATUS=1&AVS=_&TRANS_ID=100134203760&CVV2=_&MESSAGE=Approved%20Capture'
  end

  def successful_refund_response
    'AUTH_CODE=GFOCD&PAYMENT_ACCOUNT_MASK=xxxxxxxxxxxx4242&CARD_TYPE=VISA&TRANS_TYPE=CREDIT&REBID=&STATUS=1&AVS=_&TRANS_ID=100134230412&CVV2=_&MESSAGE=Approved%20Credit'
  end

  def successful_void_response
    'AUTH_CODE=KTMHB&PAYMENT_ACCOUNT_MASK=xxxxxxxxxxxx4242&CARD_TYPE=VISA&TRANS_TYPE=VOID&REBID=&STATUS=1&AVS=_&TRANS_ID=100134203763&CVV2=_&MESSAGE=Approved%20Void'
  end

  def failed_response
    'TRANS_ID=100000000150&STATUS=0&AVS=0&CVV2=7&MESSAGE=Declined&REBID='
  end
end
