require 'test_helper'

class TsysTest < Test::Unit::TestCase
  include CommStub

  def setup
    Base.mode = :test

    @gateway = TsysGateway.new(
      login: 'test_device_id',
      password: 'test_transaction_key'
    )

    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345'
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal '123456', response.authorization
    assert_equal 'APPROVAL', response.message
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'DECLINED', response.message
  end

  def test_successful_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      sale = parsed['Sale']
      assert_equal 'test_device_id', sale['deviceID']
      assert_equal 'test_transaction_key', sale['transactionKey']
      assert_equal '4111111111111111', sale['cardNumber']
      assert_equal '100', sale['transactionAmount']
      assert_equal '12345', sale['orderNumber']
      assert_equal 'INTERNET', sale['cardDataSource']
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal '123456', response.authorization
    assert_equal 'APPROVAL', response.message
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'DECLINED', response.message
    assert_equal Gateway::STANDARD_ERROR_CODE[:processing_error], response.error_code
  end

  def test_successful_capture
    response = stub_comms do
      @gateway.capture(@amount, '123456')
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      capture = parsed['Capture']
      assert_equal '123456', capture['transactionID']
      assert_equal '100', capture['transactionAmount']
    end.respond_with(successful_capture_response)

    assert_success response
    assert_equal '123456', response.authorization
  end

  def test_successful_void
    response = stub_comms do
      @gateway.void('123456')
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      void_data = parsed['Void']
      assert_equal '123456', void_data['transactionID']
      assert_nil void_data['transactionAmount']
    end.respond_with(successful_void_response)

    assert_success response
    assert_equal '123456', response.authorization
  end

  def test_successful_refund_with_credit_card
    response = stub_comms do
      @gateway.refund(@amount, '123456', @options.merge(credit_card: @credit_card))
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      refund_data = parsed['Return']
      assert_equal '4111111111111111', refund_data['cardNumber']
      assert_equal '100', refund_data['transactionAmount']
      assert_nil refund_data['transactionID']
    end.respond_with(successful_refund_response)

    assert_success response
  end

  def test_successful_refund_with_authorization
    response = stub_comms do
      @gateway.refund(@amount, '123456', @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      refund_data = parsed['Return']
      assert_equal '123456', refund_data['transactionID']
      assert_nil refund_data['cardNumber']
    end.respond_with(successful_refund_response)

    assert_success response
  end

  def test_amount_formatting
    response = stub_comms do
      @gateway.purchase(1250, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal '1250', parsed['Sale']['transactionAmount']
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_address_handling
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, billing_address: address)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      sale = parsed['Sale']
      assert_equal '456 My Street', sale['addressLine1']
      assert_equal 'K1C2N6', sale['zip']
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_address_not_included_when_nil
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, {})
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      sale = parsed['Sale']
      assert_nil sale['addressLine1']
      assert_nil sale['zip']
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  def test_developer_id_included
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal '002745G001', parsed['Sale']['developerID']
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_authorization_indicator
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'PREAUTH', parsed['Auth']['authorizationIndicator']
    end.respond_with(successful_authorize_response)

    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'PREAUTH', parsed['Sale']['authorizationIndicator']
    end.respond_with(successful_purchase_response)
  end

  def test_authorization_indicator_not_set_for_capture
    stub_comms do
      @gateway.capture(@amount, '123456')
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_nil parsed['Capture']['authorizationIndicator']
    end.respond_with(successful_capture_response)
  end

  def test_order_id_truncation
    long_order_id = 'A' * 50
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options.merge(order_id: long_order_id))
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      order_number = parsed['Sale']['orderNumber']
      assert_equal 30, order_number.length
      assert_equal 'A' * 30, order_number
    end.respond_with(successful_purchase_response)

    assert_success response
  end

  def test_avs_result
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal 'Y', response.avs_result['code']
  end

  def test_cvv_result
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_equal 'M', response.cvv_result['code']
  end

  def test_card_data_source_defaults_to_internet
    stub_comms do
      @gateway.purchase(@amount, @credit_card, {})
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'INTERNET', parsed['Sale']['cardDataSource']
    end.respond_with(successful_purchase_response)
  end

  def test_card_data_source_override
    stub_comms do
      @gateway.purchase(@amount, @credit_card, order_source: 'TELEPHONE')
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'TELEPHONE', parsed['Sale']['cardDataSource']
    end.respond_with(successful_purchase_response)
  end

  def test_currency_code_included_when_provided
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options.merge(currency: 'USD'))
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'USD', parsed['Sale']['currencyCode']
    end.respond_with(successful_purchase_response)
  end

  def test_description_included_as_order_notes
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options.merge(description: 'Test purchase'))
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'Test purchase', parsed['Sale']['orderNotes']
    end.respond_with(successful_purchase_response)
  end

  def test_unparsable_json_response
    @gateway.expects(:ssl_post).returns('this is not json')

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match(/Invalid JSON response received from TSYS/, response.message)
  end

  def test_card_holder_name_sent
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'Longbob Longsen', parsed['Sale']['cardHolderName']
    end.respond_with(successful_purchase_response)
  end

  private

  def successful_purchase_response
    '{"Sale":{"status":"PASS","responseCode":"A0000","responseMessage":"APPROVAL","transactionID":"123456","addressVerificationCode":"Y","cvvVerificationCode":"M"}}'
  end

  def failed_purchase_response
    '{"Sale":{"status":"FAIL","responseCode":"D0001","responseMessage":"DECLINED","transactionID":"","addressVerificationCode":"","cvvVerificationCode":""}}'
  end

  def successful_authorize_response
    '{"Auth":{"status":"PASS","responseCode":"A0000","responseMessage":"APPROVAL","transactionID":"123456","addressVerificationCode":"Y","cvvVerificationCode":"M"}}'
  end

  def failed_authorize_response
    '{"Auth":{"status":"FAIL","responseCode":"D0001","responseMessage":"DECLINED","transactionID":"","addressVerificationCode":"","cvvVerificationCode":""}}'
  end

  def successful_capture_response
    '{"Capture":{"status":"PASS","responseCode":"A0000","responseMessage":"APPROVAL","transactionID":"123456"}}'
  end

  def successful_void_response
    '{"Void":{"status":"PASS","responseCode":"A0000","responseMessage":"APPROVAL","transactionID":"123456"}}'
  end

  def successful_refund_response
    '{"Return":{"status":"PASS","responseCode":"A0000","responseMessage":"APPROVAL","transactionID":"789012"}}'
  end

  def pre_scrubbed
    <<~TRANSCRIPT
      <- "{\\"Sale\\":{\\"deviceID\\":\\"test_device_id\\",\\"transactionKey\\":\\"test_transaction_key_abc123\\",\\"cardNumber\\":\\"4111111111111111\\",\\"expirationDate\\":\\"09#{Time.now.year + 1}\\",\\"cvv2\\":\\"123\\",\\"developerID\\":\\"002745G001\\"}}"
    TRANSCRIPT
  end

  def post_scrubbed
    <<~TRANSCRIPT
      <- "{\\"Sale\\":{\\"deviceID\\":\\"test_device_id\\",\\"transactionKey\\":\\"[FILTERED]\\",\\"cardNumber\\":\\"[FILTERED]\\",\\"expirationDate\\":\\"09#{Time.now.year + 1}\\",\\"cvv2\\":\\"[FILTERED]\\",\\"developerID\\":\\"002745G001\\"}}"
    TRANSCRIPT
  end
end
