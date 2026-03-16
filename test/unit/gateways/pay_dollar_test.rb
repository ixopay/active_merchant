require 'test_helper'

class PayDollarGatewayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PayDollarGateway.new(fixtures(:pay_dollar))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: 'order123',
      billing_address: address
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'AUTH123', response.authorization
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_response)
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Card Declined', response.message
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_response)
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
  end

  def test_purchase_sends_correct_pay_type
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/payType=N/, data)
    end.respond_with(successful_response)
  end

  def test_authorize_sends_correct_pay_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/payType=H/, data)
    end.respond_with(successful_response)
  end

  def test_sends_credit_card_data
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/cardNo=4242424242424242/, data)
      assert_match(/securityCode=123/, data)
    end.respond_with(successful_response)
  end

  def test_money_format_is_dollars
    assert_equal :dollars, PayDollarGateway.money_format
  end

  def test_supported_countries
    assert_equal ['HK', 'SG', 'MY'], PayDollarGateway.supported_countries
  end

  def test_supported_cardtypes
    assert_equal [:visa, :master, :american_express, :diners_club, :jcb], PayDollarGateway.supported_cardtypes
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end

  def test_scrub
    transcript = 'cardNo=4242424242424242&securityCode=123'
    scrubbed = @gateway.scrub(transcript)
    assert_scrubbed('4242424242424242', scrubbed)
    assert_scrubbed('123', scrubbed)
  end

  def test_format_brand_visa
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/pMethod=VISA/, data)
    end.respond_with(successful_response)
  end

  private

  def successful_response
    'successcode=0&Ref=REF123&AuthId=AUTH123&errMsg=Transaction+Successful'
  end

  def failed_response
    'successcode=1&Ref=&AuthId=&errMsg=Card+Declined'
  end
end
