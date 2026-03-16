require 'test_helper'

class IatsPaymentsBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = IatsPaymentsGateway.new(
      agent_code: 'login',
      password: 'password',
      region: 'uk'
    )
    @amount = 100
    @credit_card = credit_card
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, ip: '1.2.3.4', order_id: '1')
    end.check_request do |endpoint, data, headers|
      assert_match(/<agentCode>login<\/agentCode>/, data)
      assert_match(/<password>password<\/password>/, data)
      assert_match(/<creditCardNum>#{@credit_card.number}<\/creditCardNum>/, data)
      assert_match(/<total>1.00<\/total>/, data)
      assert_match(/<mop>VISA<\/mop>/, data)
      assert_equal 'application/soap+xml; charset=utf-8', headers['Content-Type']
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    # iATS does not have a separate authorize; purchase is the main action
    stub_comms do
      @gateway.purchase(@amount, @credit_card, ip: '1.2.3.4')
    end.check_request do |endpoint, _data, _headers|
      assert_match(/ProcessCreditCard/, endpoint)
    end.respond_with(successful_purchase_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, ip: '1.2.3.4')
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'Success', response.message
    assert_equal 'A6DE6F24', response.authorization
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, ip: '1.2.3.4')
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert response.message.include?('REJECT')
  end

  def test_avs_cvv_result_parsing
    # iATS does not return AVS/CVV codes in its standard response
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, ip: '1.2.3.4')
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_nil response.avs_result['code']
  end

  def test_supported_countries
    countries = IatsPaymentsGateway.supported_countries
    assert_includes countries, 'US'
    assert_includes countries, 'CA'
    assert_includes countries, 'GB'
    assert countries.length > 10
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover], IatsPaymentsGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'iATS Payments', IatsPaymentsGateway.display_name
  end

  private

  def successful_purchase_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
        <soap12:Body>
          <ProcessCreditCardResponse xmlns="https://www.iatspayments.com/NetGate/">
            <ProcessCreditCardResult>
              <IATSRESPONSE>
                <STATUS>Success</STATUS>
                <ERRORS />
                <PROCESSRESULT>
                  <AUTHORIZATIONRESULT> OK</AUTHORIZATIONRESULT>
                  <CUSTOMERCODE />
                  <SETTLEMENTBATCHDATE> 04/22/2014</SETTLEMENTBATCHDATE>
                  <SETTLEMENTDATE> 04/23/2014</SETTLEMENTDATE>
                  <TRANSACTIONID>A6DE6F24</TRANSACTIONID>
                </PROCESSRESULT>
              </IATSRESPONSE>
            </ProcessCreditCardResult>
          </ProcessCreditCardResponse>
        </soap12:Body>
      </soap12:Envelope>
    XML
  end

  def failed_purchase_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <soap:Body>
          <ProcessCreditCardResponse xmlns="https://www.iatspayments.com/NetGate/">
            <ProcessCreditCardResult>
              <IATSRESPONSE xmlns="">
                <STATUS>Success</STATUS>
                <ERRORS />
                <PROCESSRESULT>
                  <AUTHORIZATIONRESULT> REJECT: 15</AUTHORIZATIONRESULT>
                  <CUSTOMERCODE />
                  <SETTLEMENTBATCHDATE> 04/22/2014</SETTLEMENTBATCHDATE>
                  <SETTLEMENTDATE> 04/23/2014</SETTLEMENTDATE>
                  <TRANSACTIONID>A6DE6F24</TRANSACTIONID>
                </PROCESSRESULT>
              </IATSRESPONSE>
            </ProcessCreditCardResult>
          </ProcessCreditCardResponse>
        </soap:Body>
      </soap:Envelope>
    XML
  end
end
