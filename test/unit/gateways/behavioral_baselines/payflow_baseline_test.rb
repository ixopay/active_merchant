require 'test_helper'

class PayflowBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PayflowGateway.new(login: 'LOGIN', password: 'PASSWORD')
    @amount = 100
    @credit_card = credit_card('4242424242424242')
    @options = { billing_address: address.merge(first_name: 'Longbob', last_name: 'Longsen') }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<CardNum>4242424242424242<\/CardNum>/, data)
      assert_match(/<Sale>/, data)
      assert_match(/<TotalAmt Currency="USD">1.00<\/TotalAmt>/, data)
      assert_match(/<Vendor>LOGIN<\/Vendor>/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<Authorization>/, data)
      assert_match(/<CardNum>4242424242424242<\/CardNum>/, data)
      assert_match(/<TotalAmt Currency="USD">1.00<\/TotalAmt>/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_successful_response_parsing
    @gateway.stubs(:ssl_post).returns(successful_authorization_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert_equal 'VUJN1A6E11D9', response.authorization
  end

  def test_failed_response_parsing
    @gateway.stubs(:ssl_post).returns(failed_authorization_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Declined', response.message
  end

  def test_avs_cvv_result_parsing
    @gateway.stubs(:ssl_post).returns(successful_authorization_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Y', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  def test_supported_countries
    assert_equal %w[US CA NZ AU], PayflowGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express jcb discover diners_club], PayflowGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'PayPal Payflow Pro', PayflowGateway.display_name
  end

  private

  def successful_authorization_response
    <<~XML
      <ResponseData>
          <Result>0</Result>
          <Message>Approved</Message>
          <Partner>verisign</Partner>
          <HostCode>000</HostCode>
          <ResponseText>AP</ResponseText>
          <PnRef>VUJN1A6E11D9</PnRef>
          <IavsResult>N</IavsResult>
          <ZipMatch>Match</ZipMatch>
          <AuthCode>094016</AuthCode>
          <Vendor>ActiveMerchant</Vendor>
          <AvsResult>Y</AvsResult>
          <StreetMatch>Match</StreetMatch>
          <CvResult>Match</CvResult>
      </ResponseData>
    XML
  end

  def failed_authorization_response
    <<~XML
      <ResponseData>
          <Result>12</Result>
          <Message>Declined</Message>
          <Partner>verisign</Partner>
          <HostCode>000</HostCode>
          <ResponseText>AP</ResponseText>
          <PnRef>VUJN1A6E11D9</PnRef>
          <IavsResult>N</IavsResult>
          <ZipMatch>Match</ZipMatch>
          <AuthCode>094016</AuthCode>
          <Vendor>ActiveMerchant</Vendor>
          <AvsResult>Y</AvsResult>
          <StreetMatch>Match</StreetMatch>
          <CvResult>Match</CvResult>
      </ResponseData>
    XML
  end
end
