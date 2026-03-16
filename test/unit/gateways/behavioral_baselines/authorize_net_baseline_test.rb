require 'test_helper'

class AuthorizeNetBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = AuthorizeNetGateway.new(
      login: 'X',
      password: 'Y'
    )
    @amount = 100
    @credit_card = credit_card
    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<transactionType>authCaptureTransaction</transactionType>', data
      assert_match '<amount>1.00</amount>', data
      assert_match '<cardNumber>4242424242424242</cardNumber>', data
      assert_match '<invoiceNumber>1</invoiceNumber>', data
      assert_match '<description>Store Purchase</description>', data
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<transactionType>authOnlyTransaction</transactionType>', data
      assert_match '<amount>1.00</amount>', data
      assert_match '<cardNumber>4242424242424242</cardNumber>', data
    end.respond_with(successful_authorize_response)
  end

  def test_capture_request_structure
    stub_comms do
      @gateway.capture(@amount, '508141795#2224#purchase')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<transactionType>priorAuthCaptureTransaction</transactionType>', data
      assert_match '<amount>1.00</amount>', data
      assert_match '<refTransId>508141795</refTransId>', data
    end.respond_with(successful_capture_response)
  end

  def test_refund_request_structure
    stub_comms do
      @gateway.refund(@amount, '508141795#2224#purchase')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<transactionType>refundTransaction</transactionType>', data
      assert_match '<amount>1.00</amount>', data
      assert_match '<refTransId>508141795</refTransId>', data
      assert_match '<cardNumber>2224</cardNumber>', data
    end.respond_with(successful_purchase_response)
  end

  def test_void_request_structure
    stub_comms do
      @gateway.void('508141795#2224#purchase')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<transactionType>voidTransaction</transactionType>', data
      assert_match '<refTransId>508141795</refTransId>', data
    end.respond_with(successful_purchase_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal '508141795#2224#purchase', response.authorization
    assert_equal 'This transaction has been approved', response.message
    assert_equal '508141795', response.params['transaction_id']
    assert_equal 1, response.params['response_code']
    assert_equal '1', response.params['response_reason_code']
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal '0#0001#purchase', response.authorization
    assert_equal 'The credit card number is invalid', response.message
    assert_equal 3, response.params['response_code']
    assert_equal '6', response.params['response_reason_code']
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_equal 'Y', response.avs_result['code']
    assert_equal 'P', response.cvv_result['code']
  end

  private

  def successful_purchase_response
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <createTransactionResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="AnetApi/xml/v1/schema/AnetApiSchema.xsd">
      <refId>1</refId>
      <messages>
        <resultCode>Ok</resultCode>
        <message><code>I00001</code><text>Successful.</text></message>
      </messages>
      <transactionResponse>
        <responseCode>1</responseCode>
        <authCode>GSOFTZ</authCode>
        <avsResultCode>Y</avsResultCode>
        <cvvResultCode>P</cvvResultCode>
        <cavvResultCode>2</cavvResultCode>
        <transId>508141795</transId>
        <refTransID/>
        <transHash>655D049EE60E1766C9C28EB47CFAA389</transHash>
        <testRequest>0</testRequest>
        <accountNumber>2224</accountNumber>
        <accountType>Visa</accountType>
        <messages>
          <message><code>1</code><description>This transaction has been approved.</description></message>
        </messages>
      </transactionResponse>
      </createTransactionResponse>
    XML
  end

  def successful_authorize_response
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <createTransactionResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="AnetApi/xml/v1/schema/AnetApiSchema.xsd">
      <refId>123456</refId>
      <messages>
        <resultCode>Ok</resultCode>
        <message><code>I00001</code><text>Successful.</text></message>
      </messages>
      <transactionResponse>
        <responseCode>1</responseCode>
        <authCode>A88MS0</authCode>
        <avsResultCode>Y</avsResultCode>
        <cvvResultCode>M</cvvResultCode>
        <cavvResultCode>2</cavvResultCode>
        <transId>508141794</transId>
        <refTransID/>
        <transHash>D0EFF3F32E5ABD14A7CE6ADF32736D57</transHash>
        <testRequest>0</testRequest>
        <accountNumber>XXXX0015</accountNumber>
        <accountType>MasterCard</accountType>
        <messages>
          <message><code>1</code><description>This transaction has been approved.</description></message>
        </messages>
      </transactionResponse>
      </createTransactionResponse>
    XML
  end

  def successful_capture_response
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <createTransactionResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="AnetApi/xml/v1/schema/AnetApiSchema.xsd">
      <refId/>
      <messages>
        <resultCode>Ok</resultCode>
        <message><code>I00001</code><text>Successful.</text></message>
      </messages>
      <transactionResponse>
        <responseCode>1</responseCode>
        <authCode>UTDVHP</authCode>
        <avsResultCode>P</avsResultCode>
        <cvvResultCode/>
        <cavvResultCode/>
        <transId>2214675515</transId>
        <refTransID>2214675515</refTransID>
        <transHash>6D739029E129D87F6CEFE3B3864F6D61</transHash>
        <testRequest>0</testRequest>
        <accountNumber>2224</accountNumber>
        <accountType>Visa</accountType>
        <messages>
          <message><code>1</code><description>This transaction has been approved.</description></message>
        </messages>
      </transactionResponse>
      </createTransactionResponse>
    XML
  end

  def failed_purchase_response
    <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <createTransactionResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="AnetApi/xml/v1/schema/AnetApiSchema.xsd">
      <refId>1234567</refId>
      <messages>
        <resultCode>Error</resultCode>
        <message><code>E00027</code><text>The transaction was unsuccessful.</text></message>
      </messages>
      <transactionResponse>
        <responseCode>3</responseCode>
        <authCode/>
        <avsResultCode>P</avsResultCode>
        <cvvResultCode/>
        <cavvResultCode/>
        <transId>0</transId>
        <refTransID/>
        <transHash>7F9A0CB845632DCA5833D2F30ED02677</transHash>
        <testRequest>0</testRequest>
        <accountNumber>XXXX0001</accountNumber>
        <accountType/>
        <errors>
          <error><errorCode>6</errorCode><errorText>The credit card number is invalid.</errorText></error>
        </errors>
      </transactionResponse>
      </createTransactionResponse>
    XML
  end
end
