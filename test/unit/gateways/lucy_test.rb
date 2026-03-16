require 'test_helper'

class LucyGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = LucyGateway.new(fixtures(:lucy))
    @credit_card = credit_card
    @amount = 100
    @options = { order_id: '1', billing_address: address }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal '123456,AUTH01', response.authorization
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'DECLINE', response.message
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.capture(@amount, '123456,AUTH01')
    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.void('123456,AUTH01')
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.refund(@amount, '123456,AUTH01')
    assert_success response
  end

  def test_purchase_sends_correct_trans_type
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TransType=Sale/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_sends_correct_trans_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TransType=Auth/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_amount_is_sent
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/Amount=1.00/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_credit_card_data_is_sent
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/CardNum=4242424242424242/, data)
    end.respond_with(successful_purchase_response)
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

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = 'CardNum=4242424242424242&CVNum=123&Password=secret&MagData=track'
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('123', scrubbed)
    assert_scrubbed('secret', scrubbed)
    assert_scrubbed('track', scrubbed)
  end

  private

  def successful_purchase_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://localhost/SmartPayments/">
        <Result>0</Result>
        <RespMSG>Approved</RespMSG>
        <Message>APPROVAL</Message>
        <PNRef>123456</PNRef>
        <AuthCode>AUTH01</AuthCode>
        <GetAVSResult>Y</GetAVSResult>
        <GetCVResult>M</GetCVResult>
      </Response>
    XML
  end

  def failed_purchase_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://localhost/SmartPayments/">
        <Result>12</Result>
        <RespMSG>DECLINE</RespMSG>
        <Message>DECLINED</Message>
        <PNRef>654321</PNRef>
        <AuthCode></AuthCode>
        <GetAVSResult>N</GetAVSResult>
        <GetCVResult>N</GetCVResult>
      </Response>
    XML
  end
end
