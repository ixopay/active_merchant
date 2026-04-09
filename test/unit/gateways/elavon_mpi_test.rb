require 'test_helper'

class ElavonMpiTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = ElavonMpiGateway.new(
      merchant_id: 'test_merchant',
      application_key: 'test_app_key'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      order_description: 'Test order'
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
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_verify_response)
    response = @gateway.capture(@amount, 'pa_res_data;txn123', @options)

    assert_success response
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_verify_response)
    response = @gateway.capture(@amount, 'pa_res_data;txn123', @options)

    assert_failure response
  end

  def test_authorize_sends_correct_xml
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<merchantId>test_merchant</merchantId>), data
      assert_match %r(<applicationKey>test_app_key</applicationKey>), data
      assert_match %r(<accountId>4111111111111111</accountId>), data
      assert_match %r(<purchaseAmount>100</purchaseAmount>), data
      assert_match %r(<purchaseCurrency>840</purchaseCurrency>), data
      assert_match %r(<orderDescription>Test order</orderDescription>), data
    end.respond_with(successful_lookup_response)
  end

  def test_capture_sends_correct_xml
    stub_comms do
      @gateway.capture(@amount, 'pa_res_payload;txn456', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<xid>txn456</xid>), data
      assert_match %r(<paRes>pa_res_payload</paRes>), data
      assert_match %r(<merchantId>test_merchant</merchantId>), data
    end.respond_with(successful_verify_response)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '<accountId>4111111111111111</accountId><applicationKey>secret_key</applicationKey>'
    scrubbed = @gateway.scrub(transcript)

    assert_match %r(<accountId>\[FILTERED\]</accountId>), scrubbed
    assert_match %r(<applicationKey>\[FILTERED\]</applicationKey>), scrubbed
    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/secret_key/, scrubbed)
  end

  def test_test_url_used_in_test_mode
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |endpoint, _data, _headers|
      assert_match %r(testempi\.internetsecure\.com), endpoint
    end.respond_with(successful_lookup_response)
  end

  def test_default_order_description
    stub_comms do
      @gateway.authorize(@amount, @credit_card, {})
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<orderDescription></orderDescription>), data
    end.respond_with(successful_lookup_response)
  end

  def test_supported_countries
    assert_equal ['US'], ElavonMpiGateway.supported_countries
  end

  def test_supported_cardtypes
    assert_equal [:visa, :master], ElavonMpiGateway.supported_cardtypes
  end

  private

  def successful_lookup_response
    <<~XML
      <response>
        <verifyEnrollmentResponse>
          <enrolled>Y</enrolled>
          <acsURL>https://acs.example.com</acsURL>
          <payload>test_payload</payload>
        </verifyEnrollmentResponse>
      </response>
    XML
  end

  def failed_lookup_response
    <<~XML
      <response>
        <verifyEnrollmentResponse>
          <enrolled>N</enrolled>
        </verifyEnrollmentResponse>
      </response>
    XML
  end

  def successful_verify_response
    <<~XML
      <response>
        <validateParesResponse>
          <status>Y</status>
          <cavv>test_cavv</cavv>
          <eci>05</eci>
        </validateParesResponse>
      </response>
    XML
  end

  def failed_verify_response
    <<~XML
      <response>
        <validateParesResponse>
          <status>N</status>
        </validateParesResponse>
      </response>
    XML
  end
end
