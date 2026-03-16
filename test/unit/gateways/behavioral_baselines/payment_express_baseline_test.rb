require 'test_helper'

class PaymentExpressBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PaymentExpressGateway.new(login: 'LOGIN', password: 'PASSWORD')
    @amount = 100
    @credit_card = credit_card
    @options = { order_id: 'order1', billing_address: address, description: 'Store purchase' }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<CardNumber>#{@credit_card.number}<\/CardNumber>/, data)
      assert_match(/<PostUsername>LOGIN<\/PostUsername>/, data)
      assert_match(/<PostPassword>PASSWORD<\/PostPassword>/, data)
      assert_match(/<TxnType>Purchase<\/TxnType>/, data)
      assert_match(/<Amount>1.00<\/Amount>/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<TxnType>Auth<\/TxnType>/, data)
      assert_match(/<CardNumber>#{@credit_card.number}<\/CardNumber>/, data)
      assert_match(/<Amount>1.00<\/Amount>/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_post).returns(successful_authorization_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'The Transaction was approved', response.message
    assert_equal '00000004011a2478', response.authorization
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_post).returns(invalid_credentials_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'The transaction was Declined (AG)', response.message
  end

  def test_avs_cvv_result_parsing
    # PaymentExpress does not return standard AVS/CVV codes
    @gateway.expects(:ssl_post).returns(successful_authorization_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_nil response.avs_result['code']
    assert_nil response.cvv_result['code']
  end

  def test_supported_countries
    assert_equal %w[AU FJ GB HK IE MY NZ PG SG US], PaymentExpressGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express diners_club jcb], PaymentExpressGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'Windcave (formerly PaymentExpress)', PaymentExpressGateway.display_name
  end

  private

  def successful_authorization_response
    <<~RESPONSE
      <Txn>
        <Transaction success="1" reco="00" responsetext="APPROVED">
          <Authorized>1</Authorized>
          <MerchantReference>Test Transaction</MerchantReference>
          <CardName>Visa</CardName>
          <AuthCode>015921</AuthCode>
          <Amount>1.23</Amount>
          <InputCurrencyName>NZD</InputCurrencyName>
          <CardHolderName>DPS</CardHolderName>
          <TxnType>Purchase</TxnType>
          <CardNumber>411111</CardNumber>
          <TestMode>1</TestMode>
          <CardHolderHelpText>The Transaction was approved</CardHolderHelpText>
          <DpsTxnRef>00000004011a2478</DpsTxnRef>
          <DpsBillingId></DpsBillingId>
          <BillingId></BillingId>
        </Transaction>
        <ReCo>00</ReCo>
        <ResponseText>APPROVED</ResponseText>
        <HelpText>The Transaction was approved</HelpText>
        <Success>1</Success>
        <TxnRef>00000004011a2478</TxnRef>
      </Txn>
    RESPONSE
  end

  def invalid_credentials_response
    '<Txn><ReCo>0</ReCo><ResponseText>Invalid Credentials</ResponseText><CardHolderHelpText>The transaction was Declined (AG)</CardHolderHelpText></Txn>'
  end
end
