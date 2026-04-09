require 'test_helper'

class OrbitalGatewayBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = ActiveMerchant::Billing::OrbitalGateway.new(
      login: 'login',
      password: 'password',
      merchant_id: 'test12'
    )
    @amount = 100
    @credit_card = credit_card('4556761029983886')
    @options = {
      order_id: '1',
      billing_address: address
    }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<MessageType>AC</MessageType>', data
      assert_match '<AccountNum>4556761029983886</AccountNum>', data
      assert_match '<Amount>100</Amount>', data
      assert_match '<OrderID>1</OrderID>', data
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<MessageType>A</MessageType>', data
      assert_match '<AccountNum>4556761029983886</AccountNum>', data
      assert_match '<Amount>100</Amount>', data
    end.respond_with(successful_purchase_response)
  end

  def test_capture_request_structure
    stub_comms do
      @gateway.capture(@amount, '4A5398CF9B87744GG84A1D30F2F2321C66249416;1;VI')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<MarkForCapture>', data
      assert_match '<TxRefNum>4A5398CF9B87744GG84A1D30F2F2321C66249416</TxRefNum>', data
      assert_match '<Amount>100</Amount>', data
    end.respond_with(successful_purchase_response)
  end

  def test_refund_request_structure
    stub_comms do
      @gateway.refund(@amount, '4A5398CF9B87744GG84A1D30F2F2321C66249416;1;VI', order_id: '1')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<TxRefNum>4A5398CF9B87744GG84A1D30F2F2321C66249416</TxRefNum>', data
      assert_match '<Amount>100</Amount>', data
    end.respond_with(successful_refund_response)
  end

  def test_void_request_structure
    stub_comms do
      @gateway.void('4A5398CF9B87744GG84A1D30F2F2321C66249416;1;VI')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<TxRefNum>4A5398CF9B87744GG84A1D30F2F2321C66249416</TxRefNum>', data
      assert_match '<Reversal>', data
    end.respond_with(successful_void_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'Approved', response.message
    assert_equal '4A5398CF9B87744GG84A1D30F2F2321C66249416;1;VI', response.authorization
    assert_equal '0', response.params['proc_status']
    assert_equal '1', response.params['approval_status']
    assert_equal '00', response.params['resp_code']
    assert_equal '091922', response.params['auth_code']
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'AUTH DECLINED                   12001', response.message
    assert_equal '0', response.params['proc_status']
    assert_equal '0', response.params['approval_status']
    assert_equal '05', response.params['resp_code']
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_equal 'H', response.avs_result['code']
    assert_equal 'N', response.cvv_result['code']
  end

  private

  def successful_purchase_response
    '<?xml version="1.0" encoding="UTF-8"?><Response><NewOrderResp><IndustryType></IndustryType><MessageType>AC</MessageType><MerchantID>700000000000</MerchantID><TerminalID>001</TerminalID><CardBrand>VI</CardBrand><AccountNum>4111111111111111</AccountNum><OrderID>1</OrderID><TxRefNum>4A5398CF9B87744GG84A1D30F2F2321C66249416</TxRefNum><TxRefIdx>1</TxRefIdx><ProcStatus>0</ProcStatus><ApprovalStatus>1</ApprovalStatus><RespCode>00</RespCode><AVSRespCode>H </AVSRespCode><CVV2RespCode>N</CVV2RespCode><AuthCode>091922</AuthCode><RecurringAdviceCd></RecurringAdviceCd><CAVVRespCode></CAVVRespCode><StatusMsg>Approved</StatusMsg><RespMsg></RespMsg><HostRespCode>00</HostRespCode><HostAVSRespCode>Y</HostAVSRespCode><HostCVV2RespCode>N</HostCVV2RespCode><CustomerRefNum></CustomerRefNum><CustomerName></CustomerName><ProfileProcStatus></ProfileProcStatus><CustomerProfileMessage></CustomerProfileMessage><RespTime>144951</RespTime></NewOrderResp></Response>'
  end

  def failed_purchase_response
    '<?xml version="1.0" encoding="UTF-8"?><Response><NewOrderResp><IndustryType></IndustryType><MessageType>AC</MessageType><MerchantID>700000000000</MerchantID><TerminalID>001</TerminalID><CardBrand>VI</CardBrand><AccountNum>4000300011112220</AccountNum><OrderID>1</OrderID><TxRefNum>4A5398CF9B87744GG84A1D30F2F2321C66249416</TxRefNum><TxRefIdx>0</TxRefIdx><ProcStatus>0</ProcStatus><ApprovalStatus>0</ApprovalStatus><RespCode>05</RespCode><AVSRespCode>G </AVSRespCode><CVV2RespCode>N</CVV2RespCode><AuthCode></AuthCode><RecurringAdviceCd></RecurringAdviceCd><CAVVRespCode></CAVVRespCode><StatusMsg>Do Not Honor</StatusMsg><RespMsg>AUTH DECLINED                   12001</RespMsg><HostRespCode>05</HostRespCode><HostAVSRespCode>N</HostAVSRespCode><HostCVV2RespCode>N</HostCVV2RespCode><CustomerRefNum></CustomerRefNum><CustomerName></CustomerName><ProfileProcStatus></ProfileProcStatus><CustomerProfileMessage></CustomerProfileMessage><RespTime>150214</RespTime></NewOrderResp></Response>'
  end

  def successful_void_response
    '<?xml version="1.0" encoding="UTF-8"?><Response><ReversalResp><MerchantID>700000208761</MerchantID><TerminalID>001</TerminalID><OrderID>2</OrderID><TxRefNum>50FB1C41FEC9D016FF0BEBAD0884B174AD0853B0</TxRefNum><TxRefIdx>1</TxRefIdx><OutstandingAmt>0</OutstandingAmt><ProcStatus>0</ProcStatus><StatusMsg></StatusMsg><RespTime>01192013172049</RespTime></ReversalResp></Response>'
  end

  def successful_refund_response
    '<?xml version="1.0" encoding="UTF-8"?><Response><NewOrderResp><IndustryType></IndustryType><MessageType>R</MessageType><MerchantID>253997</MerchantID><TerminalID>001</TerminalID><CardBrand>VI</CardBrand><AccountNum>4556761029983886</AccountNum><OrderID>0c1792db5d167e0b96dd9c</OrderID><TxRefNum>60D1E12322FD50E1517A2598593A48EEA9965469</TxRefNum><TxRefIdx>2</TxRefIdx><ProcStatus>0</ProcStatus><ApprovalStatus>1</ApprovalStatus><RespCode>00</RespCode><AVSRespCode>3 </AVSRespCode><CVV2RespCode> </CVV2RespCode><AuthCode>tst743</AuthCode><RecurringAdviceCd></RecurringAdviceCd><CAVVRespCode></CAVVRespCode><StatusMsg>Approved</StatusMsg><RespMsg></RespMsg><HostRespCode>100</HostRespCode><HostAVSRespCode>  </HostAVSRespCode><HostCVV2RespCode>  </HostCVV2RespCode><CustomerRefNum></CustomerRefNum><CustomerName></CustomerName><ProfileProcStatus></ProfileProcStatus><CustomerProfileMessage></CustomerProfileMessage><RespTime>090955</RespTime><PartialAuthOccurred></PartialAuthOccurred><RequestedAmount></RequestedAmount><RedeemedAmount></RedeemedAmount><RemainingBalance></RemainingBalance><CountryFraudFilterStatus></CountryFraudFilterStatus><IsoCountryCode></IsoCountryCode></NewOrderResp></Response>'
  end
end
