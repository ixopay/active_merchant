require 'test_helper'

class PaymentBrandsTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PaymentBrandsGateway.new(
      login: 'test_user',
      password: 'test_pass'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345'
    }
  end

  def test_successful_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'Transaction Approved', response.message
    assert_equal '12345678', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'Transaction Declined', response.message
  end

  def test_successful_authorize
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_success response
    assert_equal 'Transaction Approved', response.message
  end

  def test_successful_capture
    response = stub_comms do
      @gateway.capture(@amount, '12345678', @options)
    end.respond_with(successful_capture_response)

    assert_success response
  end

  def test_successful_refund
    response = stub_comms do
      @gateway.refund(@amount, '12345678', @options)
    end.respond_with(successful_refund_response)

    assert_success response
  end

  def test_successful_void
    response = stub_comms do
      @gateway.void('12345678', @options)
    end.respond_with(successful_void_response)

    assert_success response
  end

  def test_purchase_sends_correct_request_type
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'Sale', parsed['requestType']
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_sends_correct_request_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'Authorization', parsed['requestType']
    end.respond_with(successful_authorize_response)
  end

  def test_credentials_included_in_request
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'test_user', parsed['credentials']['username']
      assert_equal 'test_pass', parsed['credentials']['password']
    end.respond_with(successful_purchase_response)
  end

  def test_credit_card_data_included
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal '4111111111111111', parsed['creditcard']['cardNumber']
      assert_equal 'Visa', parsed['creditcard']['cardType']
    end.respond_with(successful_purchase_response)
  end

  def test_amount_format_dollars
    stub_comms do
      @gateway.purchase(100, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal '1.00', parsed['transactionAmount']
    end.respond_with(successful_purchase_response)
  end

  def test_headers_set_correctly
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, _data, headers|
      assert_equal 'application/json', headers['Content-Type']
      assert_equal 'application/json', headers['Accept']
    end.respond_with(successful_purchase_response)
  end

  def test_avs_result_returned
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_equal 'Y', response.avs_result['code']
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '{"creditcard":{"cardNumber":"4111111111111111","cvv2":"123"},"credentials":{"password":"secret"}}'
    scrubbed = @gateway.scrub(transcript)

    assert_match(/"cardNumber"\s*:\s*"\[FILTERED\]"/, scrubbed)
    assert_match(/"cvv2"\s*:\s*"\[FILTERED\]"/, scrubbed)
    assert_match(/"password"\s*:\s*"\[FILTERED\]"/, scrubbed)
    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/"123"/, scrubbed)
  end

  private

  def successful_purchase_response
    '{"result":"ok","resultMessage":"Transaction Approved","orderId":"12345678","externalAvsResponseCode":"Y","externalCvvResponseCode":"M"}'
  end

  def failed_purchase_response
    '{"result":"error","resultMessage":"Transaction Declined","orderId":"12345678"}'
  end

  def successful_authorize_response
    '{"result":"ok","resultMessage":"Transaction Approved","orderId":"12345678","externalAvsResponseCode":"Y"}'
  end

  def successful_capture_response
    '{"result":"ok","resultMessage":"Settlement Approved","orderId":"12345678"}'
  end

  def successful_refund_response
    '{"result":"ok","resultMessage":"Credit Approved","orderId":"12345678"}'
  end

  def successful_void_response
    '{"result":"ok","resultMessage":"Void Approved","orderId":"12345678"}'
  end
end
