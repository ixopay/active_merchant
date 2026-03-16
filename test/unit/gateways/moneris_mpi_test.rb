require 'test_helper'

class MonerisMpiGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MonerisMpiGateway.new(fixtures(:moneris_mpi))
    @credit_card = credit_card
    @amount = 100
    @options = { transaction_id: 'txn123' }
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
    response = @gateway.capture(@amount, 'paresdata;txn123')
    assert_success response
  end

  def test_authorize_requires_transaction_id
    assert_raises(ArgumentError) do
      @gateway.authorize(@amount, @credit_card, {})
    end
  end

  def test_authorize_sends_payment_data
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/pan/, data)
      assert_match(/expdate/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_capture_splits_authorization
    stub_comms do
      @gateway.capture(@amount, 'paresvalue;txn456')
    end.check_request do |_endpoint, data, _headers|
      assert_match(/PaRes/, data)
      assert_match(/paresvalue/, data)
      assert_match(/txn456/, data)
    end.respond_with(successful_capture_response)
  end

  def test_supported_countries
    assert_equal ['US'], MonerisMpiGateway.supported_countries
  end

  def test_supported_cardtypes
    assert_equal [:visa, :master, :american_express, :discover], MonerisMpiGateway.supported_cardtypes
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = '<pan>4242424242424242</pan><api_token>secret</api_token>'
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('secret', scrubbed)
  end

  private

  def successful_authorize_response
    '<MpiResponse><success>true</success><message>Approved</message></MpiResponse>'
  end

  def failed_response
    '<MpiResponse><success>false</success><message>Card enrollment failed</message></MpiResponse>'
  end

  def successful_capture_response
    '<MpiResponse><success>true</success><message>Authentication successful</message></MpiResponse>'
  end
end
