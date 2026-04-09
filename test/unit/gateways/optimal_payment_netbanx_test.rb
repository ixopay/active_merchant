require 'test_helper'

class OptimalPaymentNetbanxGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = OptimalPaymentNetbanxGateway.new(fixtures(:optimal_payment_netbanx))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: 'order123',
      billing_address: address,
      email: 'test@example.com'
    }
    @authorization = 'auth-id-123'
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'txn-id-123', response.authorization
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Card declined', response.message
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.capture(@amount, @authorization, @options)
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.refund(@amount, @authorization, @options)
    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.void(@authorization, @options)
    assert_success response
  end

  def test_purchase_sends_settle_with_auth
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal true, parsed['settleWithAuth']
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_does_not_send_settle_with_auth
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_nil parsed['settleWithAuth']
    end.respond_with(successful_authorize_response)
  end

  def test_sends_billing_address
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert parsed['billingDetails']
      assert_equal 'Ottawa', parsed['billingDetails']['city']
    end.respond_with(successful_purchase_response)
  end

  def test_handles_json_parse_error
    @gateway.expects(:ssl_post).returns('not json at all')
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match(/Invalid JSON/, response.message)
  end

  def test_supported_countries
    assert_equal ['US', 'CA'], OptimalPaymentNetbanxGateway.supported_countries
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = '{"cardNum":"4242424242424242","cvv":"123"}\nAuthorization: Basic dGVzdA=='
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('123', scrubbed)
    assert_scrubbed('dGVzdA==', scrubbed)
  end

  private

  def successful_purchase_response
    '{"id":"txn-id-123","status":"COMPLETED","avsResponse":"MATCH","cvvVerification":"MATCH"}'
  end

  def successful_authorize_response
    '{"id":"auth-id-123","status":"HELD"}'
  end

  def failed_response
    '{"error":{"message":"Card declined","code":"3009"}}'
  end
end
