require 'test_helper'

class CredomaticTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = CredomaticGateway.new(
      user: 'test_user',
      public_key: 'test_public_key',
      private_key: 'test_private_key',
      test: false
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      order_id: 'order123',
      billing_address: address
    }
  end

  def test_raises_in_test_mode
    assert_raise(ArgumentError) do
      CredomaticGateway.new(
        user: 'test_user',
        public_key: 'test_public_key',
        private_key: 'test_private_key',
        test: true
      )
    end
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert response.authorization.present?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).twice.returns(successful_authorize_response).then.returns(successful_capture_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_void_response)
    response = @gateway.void("100;txn123;order123", @options)

    assert_success response
  end

  def test_authorize_sends_correct_fields
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(username=test_user), data
      assert_match %r(key_id=test_public_key), data
      assert_match %r(type=auth), data
      assert_match %r(ccnumber=4111111111111111), data
      assert_match %r(orderid=order123), data
    end.respond_with(successful_authorize_response)
  end

  def test_void_requires_authorization
    assert_raise(ArgumentError) do
      @gateway.void(nil, @options)
    end
  end

  def test_capture_requires_credit_card
    assert_raise(ArgumentError) do
      @gateway.capture(@amount, '100;txn123', @options)
    end
  end

  def test_capture_uses_credit_card_from_options
    @gateway.expects(:ssl_post).returns(successful_capture_response)
    response = @gateway.capture(@amount, '100;txn123', @options.merge(credit_card: @credit_card))

    assert_success response
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = 'ccnumber=4111111111111111&cvv=123&key_id=test_public_key&other=data'
    scrubbed = @gateway.scrub(transcript)

    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/cvv=123/, scrubbed)
    assert_no_match(/key_id=test_public_key/, scrubbed)
    assert_match(/ccnumber=\[FILTERED\]/, scrubbed)
    assert_match(/cvv=\[FILTERED\]/, scrubbed)
    assert_match(/key_id=\[FILTERED\]/, scrubbed)
  end

  def test_authorization_format
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    parts = response.authorization.split(';')
    assert_equal 3, parts.length, 'Authorization should have 3 parts: amount;transactionid;orderid'
  end

  def test_message_from_response
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_match %r(SUCCESS), response.message
  end

  private

  def successful_authorize_response
    'response=1&responsetext=SUCCESS&response_code=100&transactionid=txn123&orderid=order123&avsresponse=Y&cvvresponse=M&time=1234567890'
  end

  def failed_authorize_response
    'response=2&responsetext=DECLINE&response_code=200&transactionid=txn456&orderid=order123&avsresponse=&cvvresponse=&time=1234567890'
  end

  def successful_capture_response
    'response=1&responsetext=SUCCESS&response_code=100&transactionid=txn789&orderid=order123&avsresponse=&cvvresponse=&time=1234567890'
  end

  def successful_void_response
    'response=1&responsetext=SUCCESS&response_code=100&transactionid=txn101&orderid=order123&avsresponse=&cvvresponse=&time=1234567890'
  end
end
