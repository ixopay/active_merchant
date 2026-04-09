require 'test_helper'

class MonerisBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MonerisGateway.new(login: 'store3', password: 'yesguy')
    @amount = 100
    @credit_card = credit_card('4242424242424242')
    @options = { order_id: '1', customer: '1', billing_address: address }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<store_id>store3<\/store_id>/, data)
      assert_match(/<api_token>yesguy<\/api_token>/, data)
      assert_match(/<pan>#{@credit_card.number}<\/pan>/, data)
      assert_match(/<amount>1.00<\/amount>/, data)
      assert_match(/<purchase>/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<preauth>/, data)
      assert_match(/<pan>#{@credit_card.number}<\/pan>/, data)
      assert_match(/<amount>1.00<\/amount>/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_equal '58-0_3;1026.1', response.authorization
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_avs_cvv_result_parsing
    # Moneris AVS/CVV is only available with avs_enabled/cvv_enabled options
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_supported_countries
    assert_equal ['CA'], MonerisGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express diners_club discover], MonerisGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'Moneris', MonerisGateway.display_name
  end

  private

  def successful_purchase_response
    <<~RESPONSE
      <?xml version="1.0"?>
      <response>
        <receipt>
          <ReceiptId>1026.1</ReceiptId>
          <ReferenceNum>661221050010170010</ReferenceNum>
          <ResponseCode>027</ResponseCode>
          <ISO>01</ISO>
          <AuthCode>013511</AuthCode>
          <TransTime>18:41:13</TransTime>
          <TransDate>2008-01-05</TransDate>
          <TransType>00</TransType>
          <Complete>true</Complete>
          <Message>APPROVED * =</Message>
          <TransAmount>1.00</TransAmount>
          <CardType>V</CardType>
          <TransID>58-0_3</TransID>
          <TimedOut>false</TimedOut>
        </receipt>
      </response>
    RESPONSE
  end

  def failed_purchase_response
    <<~RESPONSE
      <?xml version="1.0"?>
      <response>
        <receipt>
          <ReceiptId>1026.1</ReceiptId>
          <ReferenceNum>661221050010170010</ReferenceNum>
          <ResponseCode>481</ResponseCode>
          <ISO>01</ISO>
          <AuthCode>013511</AuthCode>
          <TransTime>18:41:13</TransTime>
          <TransDate>2008-01-05</TransDate>
          <TransType>00</TransType>
          <Complete>true</Complete>
          <Message>DECLINED * =</Message>
          <TransAmount>1.00</TransAmount>
          <CardType>V</CardType>
          <TransID>97-2-0</TransID>
          <TimedOut>false</TimedOut>
        </receipt>
      </response>
    RESPONSE
  end
end
