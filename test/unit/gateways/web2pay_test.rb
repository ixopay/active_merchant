require 'test_helper'

class Web2PayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = Web2payGateway.new(
      login: 'test_merchant',
      password: 'test_validation_code'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345'
    }
  end

  def test_successful_authorize
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(successful_response)

    assert_success response
    assert_equal 'Approved', response.message
    assert_equal '12345;AUTH01', response.authorization
    assert response.test?
  end

  def test_successful_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_response)

    assert_success response
    assert_equal 'Approved', response.message
  end

  def test_failed_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_response)

    assert_failure response
    assert_equal 'Declined', response.message
  end

  def test_successful_capture
    response = stub_comms do
      @gateway.capture(@amount, '12345;AUTH01', @options)
    end.respond_with(successful_response)

    assert_success response
  end

  def test_capture_splits_authorization
    stub_comms do
      @gateway.capture(@amount, 'TX999;CODE99', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TxID=TX999/, data)
      assert_match(/AuthorisationCode=CODE99/, data)
    end.respond_with(successful_response)
  end

  def test_credentials_in_post_data
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/eMerchantID=test_merchant/, data)
      assert_match(/ValidationCode=test_validation_code/, data)
    end.respond_with(successful_response)
  end

  def test_credit_card_in_request
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/CardNumber=4111111111111111/, data)
      assert_match(/CardCvv2=123/, data)
    end.respond_with(successful_response)
  end

  def test_expdate_format
    card = credit_card('4111111111111111', year: 2029, month: 11)
    stub_comms do
      @gateway.purchase(@amount, card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/CardExpiryYYMM=2911/, data)
    end.respond_with(successful_response)
  end

  def test_address_data
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/CardHolderAddress1/, data)
      assert_match(/CardHolderCity/, data)
      assert_match(/CardHolderState/, data)
      assert_match(/CardHolderPostalCode/, data)
    end.respond_with(successful_response)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = 'CardNumber=4111111111111111&CardCvv2=123&ValidationCode=secret123'
    scrubbed = @gateway.scrub(transcript)

    assert_match(/CardNumber=\[FILTERED\]/, scrubbed)
    assert_match(/CardCvv2=\[FILTERED\]/, scrubbed)
    assert_match(/ValidationCode=\[FILTERED\]/, scrubbed)
    assert_no_match(/4111111111111111/, scrubbed)
  end

  def test_supported_countries
    assert_include Web2payGateway.supported_countries, 'US'
  end

  def test_supported_cardtypes
    assert_include Web2payGateway.supported_cardtypes, :visa
    assert_include Web2payGateway.supported_cardtypes, :master
  end

  def test_display_name
    assert_equal 'Web2Pay', Web2payGateway.display_name
  end

  def test_avs_result
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_response)

    assert_equal 'Y', response.avs_result['code']
  end

  def test_cvv_result
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_response)

    assert_equal 'M', response.cvv_result['code']
  end

  private

  def successful_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <Web2PayResult>
        <ReturnCode>0</ReturnCode>
        <ReturnText>Approved</ReturnText>
        <TxID>12345</TxID>
        <AuthorisationCode>AUTH01</AuthorisationCode>
        <Cvv2ResultCode>M</Cvv2ResultCode>
        <AvsResultCode>Y</AvsResultCode>
      </Web2PayResult>
    XML
  end

  def failed_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <Web2PayResult>
        <ReturnCode>1</ReturnCode>
        <ReturnText>Declined</ReturnText>
      </Web2PayResult>
    XML
  end
end
