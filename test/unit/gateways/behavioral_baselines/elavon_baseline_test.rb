require 'test_helper'

class ElavonBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = ElavonGateway.new(
      login: 'login',
      user: 'user',
      password: 'password'
    )
    @amount = 100
    @credit_card = credit_card
    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<ssl_transaction_type>CCSALE</ssl_transaction_type>', data
      assert_match '<ssl_amount>1.00</ssl_amount>', data
      assert_match '<ssl_card_number>4242424242424242</ssl_card_number>', data
      assert_match '<ssl_cvv2cvc2>123</ssl_cvv2cvc2>', data
      assert_match '<ssl_exp_date>09', data
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<ssl_transaction_type>CCAUTHONLY</ssl_transaction_type>', data
      assert_match '<ssl_amount>1.00</ssl_amount>', data
      assert_match '<ssl_card_number>4242424242424242</ssl_card_number>', data
    end.respond_with(successful_authorization_response)
  end

  def test_capture_request_structure
    stub_comms do
      @gateway.capture(@amount, '093840;180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<ssl_transaction_type>CCCOMPLETE</ssl_transaction_type>', data
      assert_match '<ssl_amount>1.00</ssl_amount>', data
      assert_match '<ssl_txn_id>180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E</ssl_txn_id>', data
    end.respond_with(successful_capture_response)
  end

  def test_refund_request_structure
    stub_comms do
      @gateway.refund(@amount, '093840;180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<ssl_transaction_type>CCRETURN</ssl_transaction_type>', data
      assert_match '<ssl_amount>1.00</ssl_amount>', data
      assert_match '<ssl_txn_id>180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E</ssl_txn_id>', data
    end.respond_with(successful_refund_response)
  end

  def test_void_request_structure
    stub_comms do
      @gateway.void('093840;180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<ssl_transaction_type>CCDELETE</ssl_transaction_type>', data
      assert_match '<ssl_txn_id>180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E</ssl_txn_id>', data
    end.respond_with(successful_void_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal '093840;180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E', response.authorization
    assert_equal 'APPROVAL', response.message
    assert_equal '0', response.params['result']
    assert_equal '093840', response.params['approval_code']
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'The Credit Card Number supplied in the authorization request appears to be invalid.', response.message
    assert_equal '5000', response.params['errorCode']
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_equal 'M', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  private

  def successful_purchase_response
    <<-XML
      <txn>
        <ssl_issuer_response>00</ssl_issuer_response>
        <ssl_last_name>Longsen</ssl_last_name>
        <ssl_company>Widgets Inc</ssl_company>
        <ssl_phone>(555)555-5555</ssl_phone>
        <ssl_card_number>41**********9990</ssl_card_number>
        <ssl_result>0</ssl_result>
        <ssl_txn_id>180820AD3-27AEE6EF-8CA7-4811-8D1F-E420C3B5041E</ssl_txn_id>
        <ssl_avs_response>M</ssl_avs_response>
        <ssl_approval_code>093840</ssl_approval_code>
        <ssl_email>paul@domain.com</ssl_email>
        <ssl_amount>100.00</ssl_amount>
        <ssl_txn_time>08/18/2020 06:31:42 PM</ssl_txn_time>
        <ssl_exp_date>0921</ssl_exp_date>
        <ssl_card_short_description>VISA</ssl_card_short_description>
        <ssl_card_type>CREDITCARD</ssl_card_type>
        <ssl_transaction_type>AUTHONLY</ssl_transaction_type>
        <ssl_result_message>APPROVAL</ssl_result_message>
        <ssl_first_name>Longbob</ssl_first_name>
        <ssl_cvv2_response>M</ssl_cvv2_response>
        <ssl_partner_app_id>VM</ssl_partner_app_id>
      </txn>
    XML
  end

  def successful_authorization_response
    <<-XML
    <txn>
      <ssl_issuer_response>00</ssl_issuer_response>
      <ssl_transaction_type>AUTHONLY</ssl_transaction_type>
      <ssl_card_number>41**********9990</ssl_card_number>
      <ssl_result>0</ssl_result>
      <ssl_txn_id>150920ED4-3EB7A2DF-A5A7-48E6-97B6-D98A9DC0BD59</ssl_txn_id>
      <ssl_avs_response>M</ssl_avs_response>
      <ssl_approval_code>259404</ssl_approval_code>
      <ssl_amount>100.00</ssl_amount>
      <ssl_result_message>APPROVAL</ssl_result_message>
      <ssl_cvv2_response>M</ssl_cvv2_response>
    </txn>
    XML
  end

  def successful_capture_response
    <<-XML
      <txn>
        <ssl_result>0</ssl_result>
        <ssl_txn_id>110820ED4-23CA2F2B-A88C-40E1-AC46-9219F800A520</ssl_txn_id>
        <ssl_approval_code>070213</ssl_approval_code>
        <ssl_amount>100.00</ssl_amount>
        <ssl_transaction_type>FORCE</ssl_transaction_type>
        <ssl_result_message>APPROVAL</ssl_result_message>
      </txn>
    XML
  end

  def successful_refund_response
    <<-XML
    <txn>
      <ssl_result>0</ssl_result>
      <ssl_txn_id>180820AD3-4BACDE38-63F3-427D-BFC1-1B3EB046056B</ssl_txn_id>
      <ssl_approval_code>094012</ssl_approval_code>
      <ssl_amount>100.00</ssl_amount>
      <ssl_transaction_type>RETURN</ssl_transaction_type>
      <ssl_result_message>APPROVAL</ssl_result_message>
    </txn>
    XML
  end

  def successful_void_response
    <<-XML
    <txn>
      <ssl_result>0</ssl_result>
      <ssl_txn_id>180820AD3-2E02E02D-A1FB-4926-A957-3930D3F7B869</ssl_txn_id>
      <ssl_amount>100.00</ssl_amount>
      <ssl_transaction_type>DELETE</ssl_transaction_type>
      <ssl_result_message>APPROVAL</ssl_result_message>
    </txn>
    XML
  end

  def failed_purchase_response
    <<-XML
    <txn>
      <errorCode>5000</errorCode>
      <errorName>Credit Card Number Invalid</errorName>
      <errorMessage>The Credit Card Number supplied in the authorization request appears to be invalid.</errorMessage>
    </txn>
    XML
  end
end
