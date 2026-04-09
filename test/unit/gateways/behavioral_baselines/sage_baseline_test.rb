require 'test_helper'

class SageBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = SageGateway.new(login: 'login', password: 'password')
    @amount = 100
    @credit_card = credit_card
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, order_id: '1', billing_address: address)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/C_cardnumber=#{@credit_card.number}/, data)
      assert_match(/T_amt=1.00/, data)
      assert_match(/M_id=login/, data)
      assert_match(/M_key=password/, data)
      assert_match(/T_code=01/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, order_id: '1', billing_address: address)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/T_code=02/, data)
      assert_match(/C_cardnumber=#{@credit_card.number}/, data)
      assert_match(/T_amt=1.00/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_successful_response_parsing
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, order_id: '1', billing_address: address)
    assert_success response
    assert_equal 'APPROVED 000001', response.message
    assert_equal 'B5O89VPdf0;bankcard', response.authorization
  end

  def test_failed_response_parsing
    @gateway.expects(:ssl_post).returns(declined_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, order_id: '1', billing_address: address)
    assert_failure response
    assert_equal 'DECLINED', response.message
  end

  def test_avs_cvv_result_parsing
    @gateway.expects(:ssl_post).returns(successful_authorization_response)

    response = @gateway.purchase(@amount, @credit_card, order_id: '1', billing_address: address)
    assert_equal 'X', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  def test_supported_countries
    assert_equal %w[US CA], SageGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover jcb diners_club], SageGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'http://www.sagepayments.com', SageGateway.display_name
  end

  private

  def successful_authorization_response
    "\002A911911APPROVED                        00MX001234567890\0341000\0340\034\003"
  end

  def successful_purchase_response
    "\002A000001APPROVED 000001                 10M 00B5O89VPdf0\034e81cab9e6144a160da82\0340\034\003"
  end

  def declined_purchase_response
    "\002E000002DECLINED                        10N 00A5O89kkix0\0343443d6426188f8256b8f\0340\034\003"
  end
end
