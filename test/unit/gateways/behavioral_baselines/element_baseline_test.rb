require 'test_helper'

class ElementBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = ElementGateway.new(
      account_id: '1013963',
      account_token: 'account_token',
      application_id: '5211',
      acceptor_id: '3928907',
      application_name: 'Spreedly',
      application_version: '1'
    )
    @amount = 100
    @credit_card = credit_card
    @options = { order_id: '1', billing_address: address }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<CreditCardSale/, data)
      assert_match(/<AccountID>1013963<\/AccountID>/, data)
      assert_match(/<CardNumber>#{@credit_card.number}<\/CardNumber>/, data)
      assert_match(/<TransactionAmount>1.00<\/TransactionAmount>/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<CreditCardAuthorization/, data)
      assert_match(/<CardNumber>#{@credit_card.number}<\/CardNumber>/, data)
      assert_match(/<TransactionAmount>1.00<\/TransactionAmount>/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_equal '2005831886|100', response.authorization
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Declined', response.message
  end

  def test_avs_cvv_result_parsing
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'N', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  def test_supported_countries
    assert_equal ['US'], ElementGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover diners_club jcb], ElementGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'Element', ElementGateway.display_name
  end

  private

  def successful_purchase_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><CreditCardSaleResponse xmlns="https://transaction.elementexpress.com"><response><ExpressResponseCode>0</ExpressResponseCode><ExpressResponseMessage>Approved</ExpressResponseMessage><HostResponseCode>000</HostResponseCode><HostResponseMessage>AP</HostResponseMessage><Credentials /><Batch><HostBatchID>1</HostBatchID></Batch><Card><AVSResponseCode>N</AVSResponseCode><CVVResponseCode>M</CVVResponseCode><CardLogo>Visa</CardLogo></Card><Transaction><TransactionID>2005831886</TransactionID><ApprovalNumber>000045</ApprovalNumber></Transaction></response></CreditCardSaleResponse></soap:Body></soap:Envelope>
    XML
  end

  def failed_purchase_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><CreditCardSaleResponse xmlns="https://transaction.elementexpress.com"><response><ExpressResponseCode>20</ExpressResponseCode><ExpressResponseMessage>Declined</ExpressResponseMessage><HostResponseCode>005</HostResponseCode><HostResponseMessage>DECLINED</HostResponseMessage><Credentials /><Batch /><Card /><Transaction><TransactionID>2005831887</TransactionID></Transaction></response></CreditCardSaleResponse></soap:Body></soap:Envelope>
    XML
  end

  def successful_authorize_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><CreditCardAuthorizationResponse xmlns="https://transaction.elementexpress.com"><response><ExpressResponseCode>0</ExpressResponseCode><ExpressResponseMessage>Approved</ExpressResponseMessage><HostResponseCode>000</HostResponseCode><HostResponseMessage>AP</HostResponseMessage><Credentials /><Batch><HostBatchID>1</HostBatchID></Batch><Card><AVSResponseCode>Y</AVSResponseCode><CVVResponseCode>M</CVVResponseCode><CardLogo>Visa</CardLogo></Card><Transaction><TransactionID>2005832533</TransactionID><ApprovalNumber>000046</ApprovalNumber></Transaction></response></CreditCardAuthorizationResponse></soap:Body></soap:Envelope>
    XML
  end
end
