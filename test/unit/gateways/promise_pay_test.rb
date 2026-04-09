require 'test_helper'

class PromisePayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PromisePayGateway.new(
      login: 'test_user',
      private_key: 'test_key'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      email: 'test@example.com'
    }
  end

  def test_successful_purchase
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_token_response, successful_charge_response)

    assert_success response
    assert_equal 'charge_123', response.authorization
  end

  def test_failed_token_creation
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_token_response)

    assert_failure response
    assert_match(/Error/, response.message)
  end

  def test_requires_email
    assert_raise(ArgumentError) do
      @gateway.purchase(@amount, @credit_card, {})
    end
  end

  def test_credit_card_token_request
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      if parsed['number']
        assert_equal '4111111111111111', parsed['number']
        assert parsed['cvv']
        assert parsed['expiry_month']
        assert parsed['expiry_year']
      end
    end.respond_with(successful_token_response, successful_charge_response)
  end

  def test_authorization_header_includes_basic_auth
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, _data, headers|
      assert_match(/^Basic /, headers['Authorization'])
      assert_equal 'application/json', headers['Content-Type']
    end.respond_with(successful_token_response, successful_charge_response)
  end

  def test_charge_sends_correct_amount
    stub_comms do
      @gateway.purchase(500, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      parsed = JSON.parse(data)
      if parsed['amount']
        assert_equal '500', parsed['amount']
      end
    end.respond_with(successful_token_response, successful_charge_response)
  end

  def test_message_from_successful_response
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_token_response, successful_charge_response)

    assert_equal 'completed', response.message
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '{"number":"4111111111111111","cvv":"123","routing_number":"021000021","account_number":"9876543210"}Authorization: Basic c2VjcmV0'
    scrubbed = @gateway.scrub(transcript)

    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/"123"/, scrubbed)
    assert_no_match(/9876543210/, scrubbed)
    assert_no_match(/021000021/, scrubbed)
    assert_no_match(/Basic c2VjcmV0/, scrubbed)
  end

  def test_supported_countries
    assert_include PromisePayGateway.supported_countries, 'US'
    assert_include PromisePayGateway.supported_countries, 'AU'
  end

  def test_supported_cardtypes
    assert_include PromisePayGateway.supported_cardtypes, :visa
    assert_include PromisePayGateway.supported_cardtypes, :master
  end

  private

  def successful_token_response
    '{"card_accounts":{"id":"token_abc123","active":true}}'
  end

  def failed_token_response
    '{"errors":{"number":["is invalid"]}}'
  end

  def successful_charge_response
    '{"charges":{"id":"charge_123","state":"completed"}}'
  end

  def failed_charge_response
    '{"errors":{"amount":["is required"]}}'
  end
end
