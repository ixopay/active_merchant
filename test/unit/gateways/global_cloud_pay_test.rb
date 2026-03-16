require 'test_helper'

class GlobalCloudPayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = GlobalCloudPayGateway.new(fixtures(:global_cloud_pay))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: 'ORDER001',
      billing_address: address,
      email: 'test@example.com',
      ip: '127.0.0.1'
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'TN20160101000001', response.authorization
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_authorize_sends_correct_data
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/cardNo=#{@credit_card.number}/, data)
      assert_match(/orderNo=ORDER001/, data)
      assert_match(/orderAmount=1.00/, data)
      assert_match(/signInfo=/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_authorize_includes_address
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/country=/, data)
      assert_match(/city=/, data)
      assert_match(/zip=/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_authorize_includes_email_and_ip
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/email=test%40example.com/, data)
      assert_match(/ip=127.0.0.1/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_money_format_is_dollars
    assert_equal :dollars, GlobalCloudPayGateway.money_format
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = 'cardNo=4111111111111111&cardSecurityCode=123&password=secret'
    scrubbed = @gateway.scrub(transcript)
    assert_match(/cardNo=\[FILTERED\]/, scrubbed)
    assert_match(/cardSecurityCode=\[FILTERED\]/, scrubbed)
    assert_match(/password=\[FILTERED\]/, scrubbed)
  end

  def test_signature_generation
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/signInfo=[a-f0-9]{64}/, data)
    end.respond_with(successful_authorize_response)
  end

  private

  def successful_authorize_response
    '<respon><orderStatus>1</orderStatus><orderInfo>Success</orderInfo><tradeNo>TN20160101000001</tradeNo></respon>'
  end

  def failed_authorize_response
    '<respon><orderStatus>0</orderStatus><orderInfo>Card declined</orderInfo><tradeNo></tradeNo></respon>'
  end
end
