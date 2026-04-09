require 'test_helper'

class GlobalPaymentsTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = GlobalPaymentsGateway.new(fixtures(:global_payments))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: '1',
      billing_address: address
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal '12345,ABC123', response.authorization
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'DECLINED', response.message
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    response = @gateway.capture(@amount, '12345,ABC123', @options)
    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_void_response)

    response = @gateway.void('12345,ABC123', @options)
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(@amount, '12345,ABC123', @options)
    assert_success response
  end

  def test_purchase_sends_correct_data
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TransType=Sale/, data)
      assert_match(/CardNum=#{@credit_card.number}/, data)
      assert_match(/Amount=1.00/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_sends_auth_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TransType=Auth/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_capture_sends_pnref
    stub_comms do
      @gateway.capture(@amount, '12345,ABC123', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/PNRef=12345/, data)
      assert_match(/TransType=Force/, data)
      assert_match(/<AuthCode>ABC123<\/AuthCode>/, data)
    end.respond_with(successful_capture_response)
  end

  def test_ext_data_included
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/ExtData=/, data)
      assert_match(/<Force>T<\/Force>/, data)
      assert_match(/<TermType>8BH<\/TermType>/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_money_format_is_dollars
    assert_equal :dollars, GlobalPaymentsGateway.money_format
  end

  def test_unsupported_currency_raises_error
    assert_raises(ArgumentError) do
      @gateway.purchase(@amount, @credit_card, @options.merge(currency: 'XYZ'))
    end
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = 'CardNum=4111111111111111&CVNum=123&GlobalPassword=secret&MagData=track'
    scrubbed = @gateway.scrub(transcript)
    assert_match(/CardNum=\[FILTERED\]/, scrubbed)
    assert_match(/CVNum=\[FILTERED\]/, scrubbed)
    assert_match(/GlobalPassword=\[FILTERED\]/, scrubbed)
    assert_match(/MagData=\[FILTERED\]/, scrubbed)
  end

  private

  def successful_purchase_response
    '<Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://GlobalPayments.Ecommerce.POS"><Result>0</Result><RespMSG>Approved</RespMSG><Message>AP</Message><AuthCode>ABC123</AuthCode><PNRef>12345</PNRef><GetAVSResult>Y</GetAVSResult><GetCVResult>M</GetCVResult></Response>'
  end

  def failed_purchase_response
    '<Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://GlobalPayments.Ecommerce.POS"><Result>12</Result><RespMSG>DECLINED</RespMSG><Message>DECLINED</Message><PNRef>99999</PNRef></Response>'
  end

  def successful_authorize_response
    '<Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://GlobalPayments.Ecommerce.POS"><Result>0</Result><RespMSG>Approved</RespMSG><AuthCode>DEF456</AuthCode><PNRef>67890</PNRef></Response>'
  end

  def successful_capture_response
    '<Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://GlobalPayments.Ecommerce.POS"><Result>0</Result><RespMSG>Approved</RespMSG><AuthCode>ABC123</AuthCode><PNRef>12345</PNRef></Response>'
  end

  def successful_void_response
    '<Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://GlobalPayments.Ecommerce.POS"><Result>0</Result><RespMSG>Approved</RespMSG><PNRef>12345</PNRef></Response>'
  end

  def successful_refund_response
    '<Response xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://GlobalPayments.Ecommerce.POS"><Result>0</Result><RespMSG>Approved</RespMSG><PNRef>12345</PNRef></Response>'
  end
end
