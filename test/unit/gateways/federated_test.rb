require 'test_helper'

class FederatedTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = FederatedGateway.new(fixtures(:federated))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Test purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal '123456789', response.authorization
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'DECLINE', response.message
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    response = @gateway.capture(@amount, '123456789', @options)
    assert_success response
  end

  def test_capture_requires_authorization
    assert_raises(ArgumentError) do
      @gateway.capture(@amount, nil, @options)
    end
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_void_response)

    response = @gateway.void('123456789', @options)
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(@amount, '123456789', @options)
    assert_success response
  end

  def test_refund_requires_authorization
    assert_raises(ArgumentError) do
      @gateway.refund(@amount, nil, @options)
    end
  end

  def test_purchase_sends_correct_data
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/type=sale/, data)
      assert_match(/ccnumber=#{@credit_card.number}/, data)
      assert_match(/amount=1.00/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_sends_correct_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/type=auth/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = 'ccnumber=4111111111111111&cvv=123&password=secret'
    scrubbed = @gateway.scrub(transcript)
    assert_match(/ccnumber=\[FILTERED\]/, scrubbed)
    assert_match(/cvv=\[FILTERED\]/, scrubbed)
    assert_match(/password=\[FILTERED\]/, scrubbed)
  end

  def test_test_returns_true_for_demo_credentials
    gateway = FederatedGateway.new(login: 'demo', password: 'password')
    assert gateway.send(:test?)
  end

  def test_test_returns_false_for_non_demo_credentials
    gateway = FederatedGateway.new(login: 'real_user', password: 'real_pass')
    assert !gateway.send(:test?)
  end

  private

  def successful_purchase_response
    'response=1&responsetext=SUCCESS&authcode=12345&transactionid=123456789&avsresponse=Y&cvvresponse=M&orderid=1&type=sale&response_code=100'
  end

  def failed_purchase_response
    'response=2&responsetext=DECLINE&authcode=&transactionid=987654321&avsresponse=N&cvvresponse=N&orderid=1&type=sale&response_code=200'
  end

  def successful_authorize_response
    'response=1&responsetext=SUCCESS&authcode=12345&transactionid=123456789&avsresponse=Y&cvvresponse=M&orderid=1&type=auth&response_code=100'
  end

  def successful_capture_response
    'response=1&responsetext=SUCCESS&authcode=12345&transactionid=123456789&avsresponse=&cvvresponse=&orderid=1&type=capture&response_code=100'
  end

  def successful_void_response
    'response=1&responsetext=Transaction Void Successful&authcode=12345&transactionid=123456789&avsresponse=&cvvresponse=&orderid=1&type=void&response_code=100'
  end

  def successful_refund_response
    'response=1&responsetext=SUCCESS&authcode=12345&transactionid=123456789&avsresponse=&cvvresponse=&orderid=1&type=refund&response_code=100'
  end
end
