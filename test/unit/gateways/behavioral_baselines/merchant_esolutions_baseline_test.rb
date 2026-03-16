require 'test_helper'

class MerchantESolutionsBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MerchantESolutionsGateway.new(
      login: 'login',
      password: 'password'
    )
    @amount = 100
    @credit_card = credit_card
    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_purchase_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/transaction_type=D/, data)
      assert_match(/transaction_amount=1\.00/, data)
      assert_match(/card_number=4242424242424242/, data)
      assert_match(/cvv2=123/, data)
      assert_match(/invoice_number=1/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/transaction_type=P/, data)
      assert_match(/transaction_amount=1\.00/, data)
      assert_match(/card_number=4242424242424242/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_capture_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.capture(@amount, '42e52603e4c83a55890fbbcfb92b8de1')
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/transaction_type=S/, data)
      assert_match(/transaction_amount=1\.00/, data)
      assert_match(/transaction_id=42e52603e4c83a55890fbbcfb92b8de1/, data)
    end.respond_with(successful_capture_response)
  end

  def test_refund_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.refund(@amount, '5547cc97dae23ea6ad1a4abd33445c91')
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/transaction_type=U/, data)
      assert_match(/transaction_amount=1\.00/, data)
      assert_match(/transaction_id=5547cc97dae23ea6ad1a4abd33445c91/, data)
    end.respond_with(successful_refund_response)
  end

  def test_void_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.void('5547cc97dae23ea6ad1a4abd33445c91')
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/transaction_type=V/, data)
      assert_match(/transaction_id=5547cc97dae23ea6ad1a4abd33445c91/, data)
    end.respond_with(successful_void_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_success response
    assert_equal '5547cc97dae23ea6ad1a4abd33445c91', response.authorization
    assert_equal 'This transaction has been approved', response.message
    assert_equal '000', response.params['error_code']
    assert_equal '12345A', response.params['auth_code']
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_failure response
    assert_equal 'Invalid%20I%20or%20Key%20Incomplete%20Request', response.message
    assert_equal '101', response.params['error_code']
    assert_equal 'error', response.params['transaction_id']
  end

  def test_avs_cvv_result_parsing
    @gateway.expects(:ssl_post).returns(successful_verify_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_equal '0', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  private

  def successful_purchase_response
    'transaction_id=5547cc97dae23ea6ad1a4abd33445c91&error_code=000&auth_response_text=Exact Match&auth_code=12345A'
  end

  def successful_authorization_response
    'transaction_id=42e52603e4c83a55890fbbcfb92b8de1&error_code=000&auth_response_text=Exact Match&auth_code=12345A'
  end

  def successful_refund_response
    'transaction_id=0a5ca4662ac034a59595acb61e8da025&error_code=000&auth_response_text=Credit Approved'
  end

  def successful_void_response
    'transaction_id=1b08845c6dee3fa1a73fee2a009d33a7&error_code=000&auth_response_text=Void Request Accepted'
  end

  def successful_capture_response
    'transaction_id=42e52603e4c83a55890fbbcfb92b8de1&error_code=000&auth_response_text=Settle Request Accepted'
  end

  def failed_purchase_response
    'transaction_id=error&error_code=101&auth_response_text=Invalid%20I%20or%20Key%20Incomplete%20Request'
  end

  def successful_verify_response
    'transaction_id=a5ef059bff7a3f75ac2398eea4cc73cd&error_code=085&auth_response_text=Card Ok&avs_result=0&cvv2_result=M&auth_code=T1933H'
  end
end
