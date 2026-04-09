require 'test_helper'

class DokuTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = DokuGateway.new(
      mid: 'test_mid',
      private_key: 'test_private_key'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      order_id: 'order123',
      description: 'Test purchase',
      eci: '05',
      email: 'test@example.com',
      billing_address: address
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_success response
    assert response.test?
    assert response.authorization.present?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_failure response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_void_response)
    response = @gateway.void('APPR123,order123,session456', @options)

    assert_success response
  end

  def test_purchase_sends_correct_fields
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |endpoint, data, _headers|
      assert_match %r(ReceiveMIP), endpoint
      assert_match %r(MALLID=test_mid), data
      assert_match %r(CARDNUMBER=4111111111111111), data
      assert_match %r(AMOUNT=1\.00), data
      assert_match %r(TRANSIDMERCHANT=order123), data
      assert_match %r(EMAIL=test%40example\.com), data
      assert_match %r(ECI=05), data
    end.respond_with(successful_purchase_response)
  end

  def test_void_sends_correct_fields
    stub_comms do
      @gateway.void('APPR123,order123,session456', @options)
    end.check_request do |endpoint, data, _headers|
      assert_match %r(VoidRequest), endpoint
      assert_match %r(MALLID=test_mid), data
      assert_match %r(TRANSIDMERCHANT=order123), data
      assert_match %r(SESSIONID=session456), data
    end.respond_with(successful_void_response)
  end

  def test_purchase_requires_order_id
    assert_raise(ArgumentError) do
      @gateway.purchase(@amount, @credit_card, { description: 'test', eci: '05' })
    end
  end

  def test_credit_card_number_required
    card_without_number = credit_card('')
    assert_raise(ArgumentError) do
      @gateway.purchase(@amount, card_without_number, @options)
    end
  end

  def test_money_format_is_dollars
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(AMOUNT=1\.00), data
      assert_match %r(PURCHASEAMOUNT=1\.00), data
    end.respond_with(successful_purchase_response)
  end

  def test_stop_error_response
    @gateway.expects(:ssl_post).returns('STOP')
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_failure response
    assert_match %r(STOP error), response.message
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = 'CARDNUMBER=4111111111111111&CVV2=123&WORDS=abc123def456'
    scrubbed = @gateway.scrub(transcript)

    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/CVV2=123/, scrubbed)
    assert_no_match(/WORDS=abc123def456/, scrubbed)
    assert_match(/CARDNUMBER=\[FILTERED\]/, scrubbed)
    assert_match(/CVV2=\[FILTERED\]/, scrubbed)
    assert_match(/WORDS=\[FILTERED\]/, scrubbed)
  end

  def test_authorization_format
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    parts = response.authorization.split(',')
    assert_equal 3, parts.length, 'Authorization should have 3 parts: approvalcode,transidmerchant,sessionid'
  end

  private

  def successful_purchase_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <PAYMENT_STATUS>
        <RESPONSECODE>0000</RESPONSECODE>
        <APPROVALCODE>APPR123</APPROVALCODE>
        <TRANSIDMERCHANT>order123</TRANSIDMERCHANT>
        <SESSIONID>session456</SESSIONID>
        <RESULTMSG>SUCCESS</RESULTMSG>
      </PAYMENT_STATUS>
    XML
  end

  def failed_purchase_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <PAYMENT_STATUS>
        <RESPONSECODE>5511</RESPONSECODE>
        <RESULTMSG>FAILED</RESULTMSG>
      </PAYMENT_STATUS>
    XML
  end

  def successful_void_response
    'SUCCESS'
  end
end
