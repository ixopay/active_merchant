require 'test_helper'

class GlobalOnePayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = GlobalOnePayGateway.new(fixtures(:global_one_pay))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: 'ORDER001',
      currency: 'USD',
      billing_address: address,
      email: 'test@example.com'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'UNIQUEREF123', response.authorization
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
    assert_equal 'UNIQUEREF456', response.authorization
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    response = @gateway.capture(@amount, 'UNIQUEREF456', @options)
    assert_success response
  end

  def test_capture_requires_authorization
    assert_raises(ArgumentError) do
      @gateway.capture(@amount, nil, @options)
    end
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(@amount, 'UNIQUEREF123', @options.merge(operator_id: 'OP1', reverse_reason: 'test'))
    assert_success response
  end

  def test_purchase_sends_xml
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, headers|
      assert_match(/<PAYMENT>/, data)
      assert_match(/<ORDERID>ORDER001<\/ORDERID>/, data)
      assert_match(/<CARDNUMBER>#{@credit_card.number}<\/CARDNUMBER>/, data)
      assert_equal 'application/xml', headers['Content-Type']
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_sends_preauth_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<PREAUTH>/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_error_response
    @gateway.expects(:ssl_post).returns(error_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Invalid terminal id', response.message
  end

  def test_money_format_is_dollars
    assert_equal :dollars, GlobalOnePayGateway.money_format
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = '<CARDNUMBER>4111111111111111</CARDNUMBER><CVV>123</CVV>'
    scrubbed = @gateway.scrub(transcript)
    assert_match(/<CARDNUMBER>\[FILTERED\]<\/CARDNUMBER>/, scrubbed)
    assert_match(/<CVV>\[FILTERED\]<\/CVV>/, scrubbed)
  end

  def test_capture_sends_uniqueref
    stub_comms do
      @gateway.capture(@amount, 'UNIQUEREF456', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<PREAUTHCOMPLETION>/, data)
      assert_match(/<UNIQUEREF>UNIQUEREF456<\/UNIQUEREF>/, data)
    end.respond_with(successful_capture_response)
  end

  def test_address_included_in_purchase
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<ADDRESS1>/, data)
      assert_match(/<POSTCODE>/, data)
    end.respond_with(successful_purchase_response)
  end

  private

  def successful_purchase_response
    '<PAYMENTRESPONSE><UNIQUEREF>UNIQUEREF123</UNIQUEREF><RESPONSECODE>A</RESPONSECODE><RESPONSETEXT>APPROVED</RESPONSETEXT><AVSRESPONSE>Y</AVSRESPONSE><CVVRESPONSE>M</CVVRESPONSE></PAYMENTRESPONSE>'
  end

  def failed_purchase_response
    '<PAYMENTRESPONSE><UNIQUEREF>UNIQUEREF999</UNIQUEREF><RESPONSECODE>D</RESPONSECODE><RESPONSETEXT>DECLINED</RESPONSETEXT></PAYMENTRESPONSE>'
  end

  def successful_authorize_response
    '<PREAUTHRESPONSE><UNIQUEREF>UNIQUEREF456</UNIQUEREF><RESPONSECODE>A</RESPONSECODE><RESPONSETEXT>APPROVED</RESPONSETEXT></PREAUTHRESPONSE>'
  end

  def successful_capture_response
    '<PREAUTHCOMPLETIONRESPONSE><UNIQUEREF>UNIQUEREF456</UNIQUEREF><RESPONSECODE>A</RESPONSECODE><RESPONSETEXT>APPROVED</RESPONSETEXT></PREAUTHCOMPLETIONRESPONSE>'
  end

  def successful_refund_response
    '<REFUNDRESPONSE><UNIQUEREF>UNIQUEREF789</UNIQUEREF><RESPONSECODE>A</RESPONSECODE><RESPONSETEXT>APPROVED</RESPONSETEXT></REFUNDRESPONSE>'
  end

  def error_response
    '<ERROR><ERRORSTRING>Invalid terminal id</ERRORSTRING></ERROR>'
  end
end
