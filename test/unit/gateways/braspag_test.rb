require 'test_helper'

class BraspagTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = BraspagGateway.new(
      merchant_id: 'test_merchant_id',
      private_key: 'test_private_key',
      network: 'Simulado'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      order_id: '12345',
      billing_address: address
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_request).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert_equal 'Succeeded', response.message
    assert_equal 'abc-def-ghi', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_request).returns(failed_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
  end

  def test_successful_purchase
    @gateway.expects(:ssl_request).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_success response
    assert_equal 'Succeeded', response.message
  end

  def test_successful_capture
    @gateway.expects(:ssl_request).returns(successful_capture_response)
    response = @gateway.capture(@amount, 'abc-def-ghi', @options)

    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_request).returns(successful_void_response)
    response = @gateway.void('abc-def-ghi', @options)

    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_request).returns(successful_refund_response)
    response = @gateway.refund(@amount, 'abc-def-ghi', @options)

    assert_success response
  end

  def test_authorize_sends_json_with_correct_fields
    @gateway.expects(:ssl_request).with { |method, url, body, headers|
      parsed = JSON.parse(body)
      assert_equal :post, method
      assert_equal '12345', parsed['MerchantOrderId']
      assert_equal 'CreditCard', parsed['Payment']['Type']
      assert_equal '4111111111111111', parsed['Payment']['CreditCard']['CardNumber']
      assert_equal false, parsed['Payment']['Capture']
      assert_equal 'application/json', headers['Content-Type']
      assert_equal 'test_merchant_id', headers['MerchantId']
      assert_equal 'test_private_key', headers['MerchantKey']
      true
    }.returns(successful_authorize_response)

    @gateway.authorize(@amount, @credit_card, @options)
  end

  def test_purchase_sets_capture_true
    @gateway.expects(:ssl_request).with { |_method, _url, body, _headers|
      parsed = JSON.parse(body)
      assert_equal true, parsed['Payment']['Capture']
      true
    }.returns(successful_purchase_response)

    @gateway.purchase(@amount, @credit_card, @options)
  end

  def test_capture_uses_put_method
    @gateway.expects(:ssl_request).with { |method, url, _body, _headers|
      assert_equal :put, method
      assert_match %r(abc-def-ghi/capture), url
      true
    }.returns(successful_capture_response)

    @gateway.capture(@amount, 'abc-def-ghi', @options)
  end

  def test_void_uses_put_method
    @gateway.expects(:ssl_request).with { |method, url, _body, _headers|
      assert_equal :put, method
      assert_match %r(abc-def-ghi/void), url
      true
    }.returns(successful_void_response)

    @gateway.void('abc-def-ghi', @options)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '"CardNumber": "4111111111111111", "SecurityCode": "123", MerchantKey: test_private_key'
    scrubbed = @gateway.scrub(transcript)

    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/\"123\"/, scrubbed)
    assert_no_match(/test_private_key/, scrubbed)
    assert_match(/\[FILTERED\]/, scrubbed)
  end

  private

  def successful_authorize_response
    '{"Payment":{"PaymentId":"abc-def-ghi","ReasonCode":0,"ReasonMessage":"Successful","Capture":false}}'
  end

  def failed_authorize_response
    '{"Payment":{"PaymentId":"abc-def-ghi","ReasonCode":7,"ReasonMessage":"Denied"}}'
  end

  def successful_purchase_response
    '{"Payment":{"PaymentId":"abc-def-ghi","ReasonCode":0,"ReasonMessage":"Successful","Capture":true}}'
  end

  def successful_capture_response
    '{"ReasonCode":0,"ReasonMessage":"Successful"}'
  end

  def successful_void_response
    '{"ReasonCode":0,"ReasonMessage":"Successful"}'
  end

  def successful_refund_response
    '{"ReasonCode":0,"ReasonMessage":"Successful"}'
  end
end
