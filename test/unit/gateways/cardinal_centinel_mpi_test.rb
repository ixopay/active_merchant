require 'test_helper'

class CardinalCentinelMpiTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = CardinalCentinelMpiGateway.new(
      processor_id: 'test_processor',
      merchant_id: 'test_merchant',
      password: 'test_password'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      currency_code: '840',
      order_number: 'order123'
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_lookup_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_lookup_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
    assert_equal 'Card not enrolled', response.message
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_authenticate_response)
    response = @gateway.capture(@amount, 'pa_res_data;txn123', @options)

    assert_success response
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_authenticate_response)
    response = @gateway.capture(@amount, 'pa_res_data;txn123', @options)

    assert_failure response
  end

  def test_authorize_sends_correct_xml
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(cmpi_msg=), data
      decoded = CGI.unescape(data.sub('cmpi_msg=', ''))
      assert_match %r(<MsgType>cmpi_lookup</MsgType>), decoded
      assert_match %r(<CardNumber>4111111111111111</CardNumber>), decoded
      assert_match %r(<ProcessorId>test_processor</ProcessorId>), decoded
      assert_match %r(<MerchantId>test_merchant</MerchantId>), decoded
      assert_match %r(<TransactionPwd>test_password</TransactionPwd>), decoded
      assert_match %r(<Amount>100</Amount>), decoded
    end.respond_with(successful_lookup_response)
  end

  def test_capture_sends_authenticate_message
    stub_comms do
      @gateway.capture(@amount, 'pa_res_payload;txn456', @options)
    end.check_request do |_endpoint, data, _headers|
      decoded = CGI.unescape(data.sub('cmpi_msg=', ''))
      assert_match %r(<MsgType>cmpi_authenticate</MsgType>), decoded
      assert_match %r(<TransactionId>txn456</TransactionId>), decoded
      assert_match %r(<PAResPayload>pa_res_payload</PAResPayload>), decoded
    end.respond_with(successful_authenticate_response)
  end

  def test_requires_currency_code_and_order_number
    assert_raise(ArgumentError) do
      @gateway.authorize(@amount, @credit_card, {})
    end
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '<CardNumber>4111111111111111</CardNumber><TransactionPwd>secret123</TransactionPwd>'
    scrubbed = @gateway.scrub(transcript)

    assert_match %r(<CardNumber>\[FILTERED\]</CardNumber>), scrubbed
    assert_match %r(<TransactionPwd>\[FILTERED\]</TransactionPwd>), scrubbed
    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/secret123/, scrubbed)
  end

  def test_test_url_used_in_test_mode
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |endpoint, _data, _headers|
      assert_match %r(centineltest\.cardinalcommerce\.com), endpoint
    end.respond_with(successful_lookup_response)
  end

  private

  def successful_lookup_response
    '<CardinalMPI><ErrorNo>0</ErrorNo><ErrorDesc/><TransactionId>txn123</TransactionId></CardinalMPI>'
  end

  def failed_lookup_response
    '<CardinalMPI><ErrorNo>1001</ErrorNo><ErrorDesc>Card not enrolled</ErrorDesc></CardinalMPI>'
  end

  def successful_authenticate_response
    '<CardinalMPI><ErrorNo>0</ErrorNo><ErrorDesc/><PAResStatus>Y</PAResStatus></CardinalMPI>'
  end

  def failed_authenticate_response
    '<CardinalMPI><ErrorNo>1002</ErrorNo><ErrorDesc>Authentication failed</ErrorDesc></CardinalMPI>'
  end
end
