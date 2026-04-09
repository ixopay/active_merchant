require 'test_helper'

class NmiBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = NmiGateway.new(login: 'login', password: 'password')
    @amount = 100
    @credit_card = credit_card
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/type=sale/, data)
      assert_match(/amount=1.00/, data)
      assert_match(/payment=creditcard/, data)
      assert_match(/ccnumber=#{@credit_card.number}/, data)
      assert_match(/cvv=#{@credit_card.verification_value}/, data)
      assert_match(/username=login/, data)
      assert_match(/password=password/, data)
    end.respond_with(successful_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/type=auth/, data)
      assert_match(/amount=1.00/, data)
      assert_match(/payment=creditcard/, data)
      assert_match(/ccnumber=#{@credit_card.number}/, data)
    end.respond_with(successful_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card)
    end.respond_with(successful_response)

    assert_success response
    assert_equal 'Succeeded', response.message
    assert_equal '2762757839#creditcard', response.authorization
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card)
    end.respond_with(failed_response)

    assert_failure response
    assert_equal 'DECLINE', response.message
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card)
    end.respond_with(successful_response)

    assert_equal 'N', response.avs_result['code']
    assert_equal 'N', response.cvv_result['code']
  end

  def test_supported_countries
    assert_equal %w[US CA], NmiGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover], NmiGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'NMI', NmiGateway.display_name
  end

  private

  def successful_response
    'response=1&responsetext=SUCCESS&authcode=123456&transactionid=2762757839&avsresponse=N&cvvresponse=N&orderid=b6c1c57f709cfaa65a5cf5b8532ad181&type=&response_code=100'
  end

  def failed_response
    'response=2&responsetext=DECLINE&authcode=&transactionid=2762766725&avsresponse=N&cvvresponse=N&orderid=f4bd34a5a6089aa822d13352807bdf11&type=&response_code=200'
  end
end
