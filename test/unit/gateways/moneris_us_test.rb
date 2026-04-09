require 'test_helper'

class MonerisUsGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MonerisUsGateway.new(fixtures(:moneris_us))
    @credit_card = credit_card
    @amount = 100
    @options = { order_id: 'order1' }
    @authorization = '12345;order1'
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert response.authorization.present?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.capture(@amount, @authorization)
    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.void(@authorization)
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.refund(@amount, @authorization)
    assert_success response
  end

  def test_refund_with_credit_card
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.refund(@amount, @authorization, @options.merge(credit_card: @credit_card))
    assert_success response
  end

  def test_purchase_sends_us_purchase_action
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<us_purchase>/, data)
    end.respond_with(successful_response)
  end

  def test_authorize_sends_us_preauth_action
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<us_preauth>/, data)
    end.respond_with(successful_response)
  end

  def test_store
    @gateway.expects(:ssl_post).returns(successful_store_response)
    response = @gateway.store(@credit_card)
    assert_success response
  end

  def test_unstore
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.unstore('datakey123')
    assert_success response
  end

  def test_invalid_authorization_format
    assert_raises(ArgumentError) do
      @gateway.capture(@amount, 'invalid')
    end
  end

  def test_supported_countries
    assert_equal ['US'], MonerisUsGateway.supported_countries
  end

  def test_supported_cardtypes
    assert_equal [:visa, :master, :american_express, :diners_club, :discover], MonerisUsGateway.supported_cardtypes
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = '<pan>4242424242424242</pan><cvd_value>123</cvd_value><api_token>secret</api_token>'
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('123', scrubbed)
    assert_scrubbed('secret', scrubbed)
  end

  private

  def successful_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <response>
        <receipt>
          <ReceiptId>order1</ReceiptId>
          <ReferenceNum>660110910011136190</ReferenceNum>
          <ResponseCode>027</ResponseCode>
          <ISO>01</ISO>
          <AuthCode>012345</AuthCode>
          <TransTime>15:28:51</TransTime>
          <TransDate>2015-01-01</TransDate>
          <TransType>00</TransType>
          <Complete>true</Complete>
          <Message>APPROVED * =</Message>
          <TransAmount>1.00</TransAmount>
          <CardType>V</CardType>
          <TransID>12345</TransID>
          <TimedOut>false</TimedOut>
          <AvsResultCode>null</AvsResultCode>
          <CvdResultCode>1M</CvdResultCode>
        </receipt>
      </response>
    XML
  end

  def failed_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <response>
        <receipt>
          <ReceiptId>order1</ReceiptId>
          <ResponseCode>051</ResponseCode>
          <Complete>true</Complete>
          <Message>DECLINED * =</Message>
          <TransID>12345</TransID>
        </receipt>
      </response>
    XML
  end

  def successful_store_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <response>
        <receipt>
          <DataKey>datakey123</DataKey>
          <ResponseCode>001</ResponseCode>
          <Complete>true</Complete>
          <Message>Successfully registered CC details * =</Message>
          <TransID>store1</TransID>
        </receipt>
      </response>
    XML
  end
end
