require 'test_helper'

class MerchantLinkGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MerchantLinkGateway.new(fixtures(:merchant_link))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: 'order123',
      billing_address: address,
      terminal_id: 'T001',
      lane_id: 'L001',
      transaction_index: '1',
      date: '20250101',
      time: '120000',
      posts: '001'
    }
    @authorization = 'MLTRAN123;4242'
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
    response = @gateway.capture(@amount, @authorization, @options)
    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.void(@authorization, @options)
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.refund(@amount, @authorization, @options.merge(credit_card: @credit_card))
    assert_success response
  end

  def test_refund_requires_credit_card
    assert_raises(ArgumentError) do
      @gateway.refund(@amount, @authorization, @options)
    end
  end

  def test_purchase_sends_xml_with_credit_card
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<PAN>4242424242424242<\/PAN>/, data)
      assert_match(/<CCSale>/, data)
    end.respond_with(successful_response)
  end

  def test_authorize_sends_ccauth
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<CCAuth>/, data)
    end.respond_with(successful_response)
  end

  def test_money_format_is_dollars
    assert_equal :dollars, MerchantLinkGateway.money_format
  end

  def test_failover_on_connection_error
    @gateway.expects(:ssl_post).twice.raises(ActiveMerchant::ConnectionError.new('connection failed', nil)).then.returns(successful_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_supported_countries
    assert_equal ['US'], MerchantLinkGateway.supported_countries
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = '<PAN>4242424242424242</PAN><Exp>0925</Exp><CVD>123</CVD><T1>track1data</T1><T2>track2data</T2>'
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('0925', scrubbed)
    assert_scrubbed('123', scrubbed)
    assert_scrubbed('track1data', scrubbed)
    assert_scrubbed('track2data', scrubbed)
  end

  private

  def successful_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <TV2GResponse>
        <CreditResp>
          <MLRespCode>A001</MLRespCode>
          <MLRespText>Approved</MLRespText>
          <HostRespCode>00</HostRespCode>
          <HostRespText>APPROVAL</HostRespText>
          <MLTranID>MLTRAN123</MLTranID>
          <TVKey>4242424242424242</TVKey>
          <AuthCode>AUTH01</AuthCode>
          <ZipResult>1</ZipResult>
          <AddressResult>1</AddressResult>
          <CVDResult>M</CVDResult>
        </CreditResp>
      </TV2GResponse>
    XML
  end

  def failed_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <TV2GResponse>
        <CreditResp>
          <MLRespCode>D001</MLRespCode>
          <MLRespText>Declined</MLRespText>
          <HostRespCode>05</HostRespCode>
          <HostRespText>DECLINED</HostRespText>
          <MLTranID>MLTRAN456</MLTranID>
          <TVKey>4242424242424242</TVKey>
        </CreditResp>
      </TV2GResponse>
    XML
  end
end
