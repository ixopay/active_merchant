require 'test_helper'

class MaxipagoBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MaxipagoGateway.new(login: 'login', password: 'password')
    @amount = 100
    @credit_card = credit_card
    @options = { order_id: '1', billing_address: address }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<merchantId>login<\/merchantId>/, data)
      assert_match(/<merchantKey>password<\/merchantKey>/, data)
      assert_match(/<number>#{@credit_card.number}<\/number>/, data)
      assert_match(/<sale>/, data)
      assert_match(/<chargeTotal>1.00<\/chargeTotal>/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<auth>/, data)
      assert_match(/<number>#{@credit_card.number}<\/number>/, data)
      assert_match(/<chargeTotal>1.00<\/chargeTotal>/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'CAPTURED', response.message
    assert_equal '123456789|123456789', response.authorization
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'DECLINED', response.message
  end

  def test_avs_cvv_result_parsing
    # maxiPago does not return standard AVS/CVV result codes in its response
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_supported_countries
    assert_equal ['BR'], MaxipagoGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master discover american_express diners_club], MaxipagoGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'maxiPago!', MaxipagoGateway.display_name
  end

  private

  def successful_purchase_response
    %(
      <transaction-response>
        <authCode>555555</authCode>
        <orderID>123456789</orderID>
        <referenceNum>123456789</referenceNum>
        <transactionID>123456789</transactionID>
        <transactionTimestamp>123456789</transactionTimestamp>
        <responseCode>0</responseCode>
        <responseMessage>CAPTURED</responseMessage>
        <avsResponseCode/>
        <cvvResponseCode/>
        <processorCode>0</processorCode>
        <processorMessage>APPROVED</processorMessage>
        <errorMessage/>
      </transaction-response>
    )
  end

  def failed_purchase_response
    %(
      <transaction-response>
        <authCode/>
        <orderID>123456789</orderID>
        <referenceNum>123456789</referenceNum>
        <transactionID>123456789</transactionID>
        <transactionTimestamp>123456789</transactionTimestamp>
        <responseCode>1</responseCode>
        <responseMessage>DECLINED</responseMessage>
        <avsResponseCode>NNN</avsResponseCode>
        <cvvResponseCode>N</cvvResponseCode>
        <processorCode>D</processorCode>
        <processorMessage>DECLINED</processorMessage>
        <errorMessage/>
      </transaction-response>
    )
  end

  def successful_authorize_response
    %(
      <?xml version="1.0" encoding="UTF-8"?>
      <transaction-response>
        <authCode>123456</authCode>
        <orderID>C0A8013F:014455FCC857:91A0:01A7243E</orderID>
        <referenceNum>12345</referenceNum>
        <transactionID>663921</transactionID>
        <transactionTimestamp>1393012206</transactionTimestamp>
        <responseCode>0</responseCode>
        <responseMessage>AUTHORIZED</responseMessage>
        <avsResponseCode>YYY</avsResponseCode>
        <cvvResponseCode>M</cvvResponseCode>
        <processorCode>A</processorCode>
        <processorMessage>APPROVED</processorMessage>
        <errorMessage/>
      </transaction-response>
    )
  end
end
