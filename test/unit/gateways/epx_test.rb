require 'test_helper'

class EpxTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = EpxGateway.new(fixtures(:epx))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: '1',
      billing_address: address,
      report_group: 'batch1',
      transaction_index: '001'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'APPROVED', response.message
    assert response.authorization.include?(';sale')
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
    assert response.authorization.include?(';authorization')
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    response = @gateway.capture(@amount, 'GUID123;authorization', @options)
    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_void_response)

    response = @gateway.void('GUID123;sale', @options)
    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(@amount, 'GUID123;sale', @options)
    assert_success response
  end

  def test_refund_requires_authorization
    assert_raises(ArgumentError) do
      @gateway.refund(@amount, nil, @options)
    end
  end

  def test_capture_requires_authorization
    assert_raises(ArgumentError) do
      @gateway.capture(@amount, nil, @options)
    end
  end

  def test_purchase_sends_correct_data
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/ACCOUNT_NBR=#{@credit_card.number}/, data)
      assert_match(/TRAN_TYPE=CCE1/, data)
      assert_match(/AMOUNT=1.00/, data)
      assert_match(/CVV2=#{@credit_card.verification_value}/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_moto_indicator_changes_tran_type
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options.merge(moto_ecommerce_ind: 'MOTO'))
    end.check_request do |_endpoint, data, _headers|
      assert_match(/TRAN_TYPE=CCM1/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = 'ACCOUNT_NBR=4111111111111111&CVV2=123&ROUTING_NBR=021000021&password=secret'
    scrubbed = @gateway.scrub(transcript)
    assert_match(/ACCOUNT_NBR=\[FILTERED\]/, scrubbed)
    assert_match(/CVV2=\[FILTERED\]/, scrubbed)
    assert_match(/ROUTING_NBR=\[FILTERED\]/, scrubbed)
    assert_match(/password=\[FILTERED\]/, scrubbed)
  end

  def test_money_format_is_dollars
    assert_equal :dollars, EpxGateway.money_format
  end

  def test_supports_check
    assert @gateway.supports_check?
  end

  def test_authorization_string_contains_action
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    _guid, action = response.authorization.split(';')
    assert_equal 'sale', action
  end

  private

  def successful_purchase_response
    '<RESPONSE><FIELDS><FIELD KEY="AUTH_RESP">00</FIELD><FIELD KEY="AUTH_RESP_TEXT">APPROVED</FIELD><FIELD KEY="AUTH_GUID">GUID-12345</FIELD><FIELD KEY="AUTH_AVS">Y</FIELD><FIELD KEY="AUTH_CVV2">M</FIELD></FIELDS></RESPONSE>'
  end

  def failed_purchase_response
    '<RESPONSE><FIELDS><FIELD KEY="AUTH_RESP">05</FIELD><FIELD KEY="AUTH_RESP_TEXT">DECLINED</FIELD><FIELD KEY="AUTH_GUID">GUID-99999</FIELD></FIELDS></RESPONSE>'
  end

  def successful_authorize_response
    '<RESPONSE><FIELDS><FIELD KEY="AUTH_RESP">00</FIELD><FIELD KEY="AUTH_RESP_TEXT">APPROVED</FIELD><FIELD KEY="AUTH_GUID">GUID-AUTH-1</FIELD></FIELDS></RESPONSE>'
  end

  def successful_capture_response
    '<RESPONSE><FIELDS><FIELD KEY="AUTH_RESP">00</FIELD><FIELD KEY="AUTH_RESP_TEXT">APPROVED</FIELD><FIELD KEY="AUTH_GUID">GUID-CAP-1</FIELD></FIELDS></RESPONSE>'
  end

  def successful_void_response
    '<RESPONSE><FIELDS><FIELD KEY="AUTH_RESP">00</FIELD><FIELD KEY="AUTH_RESP_TEXT">APPROVED</FIELD><FIELD KEY="AUTH_GUID">GUID-VOID-1</FIELD></FIELDS></RESPONSE>'
  end

  def successful_refund_response
    '<RESPONSE><FIELDS><FIELD KEY="AUTH_RESP">00</FIELD><FIELD KEY="AUTH_RESP_TEXT">APPROVED</FIELD><FIELD KEY="AUTH_GUID">GUID-REF-1</FIELD></FIELDS></RESPONSE>'
  end
end
