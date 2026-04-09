require 'test_helper'

class NsoftwareInPayGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = NsoftwareInPayGateway.new(fixtures(:nsoftware_in_pay))
    @credit_card = credit_card
    @amount = 100
    @options = {
      transaction_id: 'txn123',
      message_id: 'msg123',
      return_url: 'https://example.com/callback'
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_response)
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)
    response = @gateway.capture(@amount, 'pares_data;txn123', @options.merge(credit_card: @credit_card))
    assert_success response
  end

  def test_capture_requires_credit_card
    assert_raises(ArgumentError) do
      @gateway.capture(@amount, 'pares;txn123', @options)
    end
  end

  def test_authorize_requires_transaction_id
    assert_raises(ArgumentError) do
      @gateway.authorize(@amount, @credit_card, { message_id: 'msg', return_url: 'url' })
    end
  end

  def test_authorize_sends_json
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'auth-request', parsed['action']
      assert_equal 'txn123', parsed['data']['transaction_id']
      assert_equal '4242424242424242', parsed['data']['token']
    end.respond_with(successful_authorize_response)
  end

  def test_capture_sends_pares
    stub_comms do
      @gateway.capture(@amount, 'mypares;txn456', @options.merge(credit_card: @credit_card))
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      assert_equal 'auth-response', parsed['action']
      assert_equal 'mypares', parsed['data']['pares']
    end.respond_with(successful_capture_response)
  end

  def test_supported_countries
    assert_equal ['US'], NsoftwareInPayGateway.supported_countries
  end

  def test_supported_cardtypes
    assert_equal [:visa, :master, :american_express, :discover], NsoftwareInPayGateway.supported_cardtypes
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = '{"data":{"token":"4242424242424242","card_exp_month":"09","card_exp_year":"2026"}}'
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('09', scrubbed)
    assert_scrubbed('2026', scrubbed)
  end

  private

  def successful_authorize_response
    '{"AcsUrl":"https://acs.example.com","PaReq":"pareqdata","success":"true"}'
  end

  def failed_response
    '{"success":"false","error":"Authentication failed"}'
  end

  def successful_capture_response
    '{"success":"true","cavv":"cavvdata","eci":"05"}'
  end
end
