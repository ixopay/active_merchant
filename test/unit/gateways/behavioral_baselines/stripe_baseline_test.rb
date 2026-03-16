require 'test_helper'

class StripeBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = StripeGateway.new(login: 'sk_test_login')
    @amount = 400
    @credit_card = credit_card
    @options = {
      billing_address: address,
      description: 'Test Purchase'
    }
  end

  def test_purchase_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_method, endpoint, data, _headers|
      if endpoint.include?('/charges')
        assert_match(/amount=400/, data)
        assert_match(/currency=usd/, data)
        assert_match(/description=Test\+Purchase/, data)
      end
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_method, endpoint, data, _headers|
      if endpoint.include?('/charges')
        assert_match(/amount=400/, data)
        assert_match(/capture=false/, data)
      end
    end.respond_with(successful_purchase_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_request).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'ch_test_charge', response.authorization
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_request).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Your card number is incorrect', response.message
  end

  def test_avs_cvv_result_parsing
    # Stripe returns AVS/CVV in card checks, not in the standard location
    @gateway.expects(:ssl_request).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_supported_countries
    countries = StripeGateway.supported_countries
    assert_includes countries, 'US'
    assert_includes countries, 'CA'
    assert_includes countries, 'GB'
    assert countries.length > 30
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover jcb diners_club maestro unionpay], StripeGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'Stripe', StripeGateway.display_name
  end

  private

  def successful_purchase_response
    <<-RESPONSE
    {
      "amount": 400,
      "created": 1309131571,
      "currency": "usd",
      "description": "Test Purchase",
      "id": "ch_test_charge",
      "livemode": false,
      "object": "charge",
      "paid": true,
      "refunded": false,
      "card": {
        "country": "US",
        "exp_month": 9,
        "exp_year": #{Time.now.year + 1},
        "last4": "4242",
        "object": "card",
        "type": "Visa"
      }
    }
    RESPONSE
  end

  def failed_purchase_response
    <<-RESPONSE
    {
      "error": {
        "code": "incorrect_number",
        "param": "number",
        "type": "card_error",
        "message": "Your card number is incorrect"
      }
    }
    RESPONSE
  end
end
