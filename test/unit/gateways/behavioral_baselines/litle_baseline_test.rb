require 'test_helper'

class LitleBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = LitleGateway.new(
      login: 'login',
      password: 'password',
      merchant_id: 'merchant_id'
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
      assert_match '<sale ', data
      assert_match '<amount>100</amount>', data
      assert_match '<number>4242424242424242</number>', data
      assert_match '<orderId>1</orderId>', data
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<authorization ', data
      assert_match '<amount>100</amount>', data
      assert_match '<number>4242424242424242</number>', data
      assert_match '<orderId>1</orderId>', data
    end.respond_with(successful_authorize_response)
  end

  def test_capture_request_structure
    stub_comms do
      @gateway.capture(@amount, '100000000000000001;authorize')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<capture ', data
      assert_match '<litleTxnId>100000000000000001</litleTxnId>', data
    end.respond_with(successful_capture_response)
  end

  def test_refund_request_structure
    stub_comms do
      @gateway.refund(@amount, '100000000000000006;sale')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<credit ', data
      assert_match '<litleTxnId>100000000000000006</litleTxnId>', data
    end.respond_with(successful_refund_response)
  end

  def test_void_request_structure
    stub_comms do
      @gateway.void('100000000000000006;sale')
    end.check_request do |_endpoint, data, _headers|
      assert_match '<void ', data
      assert_match '<litleTxnId>100000000000000006</litleTxnId>', data
    end.respond_with(successful_void_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal '100000000000000006;sale;100', response.authorization
    assert_equal 'Approved', response.message
    assert_equal '000', response.params['response']
    assert_equal '100000000000000006', response.params['litleTxnId']
    assert_equal '11111 ', response.params['authCode']
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'Insufficient Funds', response.message
    assert_equal '110', response.params['response']
    assert_equal '600000000000000002', response.params['litleTxnId']
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_equal '01', response.params['fraudResult_avsResult']
    assert_equal 'M', response.params['fraudResult_cardValidationResult']
  end

  private

  def successful_purchase_response
    %(
      <litleOnlineResponse version='8.22' response='0' message='Valid Format' xmlns='http://www.litle.com/schema'>
        <saleResponse id='1' reportGroup='Default Report Group' customerId=''>
          <litleTxnId>100000000000000006</litleTxnId>
          <orderId>1</orderId>
          <response>000</response>
          <responseTime>2014-03-31T11:34:39</responseTime>
          <message>Approved</message>
          <authCode>11111 </authCode>
          <fraudResult>
            <avsResult>01</avsResult>
            <cardValidationResult>M</cardValidationResult>
          </fraudResult>
        </saleResponse>
      </litleOnlineResponse>
    )
  end

  def successful_authorize_response
    %(
      <litleOnlineResponse version='8.22' response='0' message='Valid Format' xmlns='http://www.litle.com/schema'>
        <authorizationResponse id='1' reportGroup='Default Report Group' customerId=''>
          <litleTxnId>100000000000000001</litleTxnId>
          <orderId>1</orderId>
          <response>000</response>
          <responseTime>2014-03-31T12:21:56</responseTime>
          <message>Approved</message>
          <authCode>11111 </authCode>
          <fraudResult>
            <avsResult>01</avsResult>
            <cardValidationResult>M</cardValidationResult>
          </fraudResult>
        </authorizationResponse>
      </litleOnlineResponse>
    )
  end

  def successful_capture_response
    %(
      <litleOnlineResponse version='8.22' response='0' message='Valid Format' xmlns='http://www.litle.com/schema'>
        <captureResponse id='' reportGroup='Default Report Group' customerId=''>
          <litleTxnId>100000000000000002</litleTxnId>
          <response>000</response>
          <responseTime>2014-03-31T12:28:07</responseTime>
          <message>Approved</message>
        </captureResponse>
      </litleOnlineResponse>
    )
  end

  def successful_refund_response
    %(
      <litleOnlineResponse version='8.22' response='0' message='Valid Format' xmlns='http://www.litle.com/schema'>
        <creditResponse id='' reportGroup='Default Report Group' customerId=''>
          <litleTxnId>100000000000000003</litleTxnId>
          <response>000</response>
          <responseTime>2014-03-31T12:36:50</responseTime>
          <message>Approved</message>
        </creditResponse>
      </litleOnlineResponse>
    )
  end

  def successful_void_response
    %(
      <litleOnlineResponse version='8.22' response='0' message='Valid Format' xmlns='http://www.litle.com/schema'>
        <voidResponse id='' reportGroup='Default Report Group' customerId=''>
          <litleTxnId>100000000000000004</litleTxnId>
          <response>000</response>
          <responseTime>2014-03-31T12:44:52</responseTime>
          <message>Approved</message>
        </voidResponse>
      </litleOnlineResponse>
    )
  end

  def failed_purchase_response
    %(
      <litleOnlineResponse version='8.22' response='0' message='Valid Format' xmlns='http://www.litle.com/schema'>
        <saleResponse id='6' reportGroup='Default Report Group' customerId=''>
          <litleTxnId>600000000000000002</litleTxnId>
          <orderId>6</orderId>
          <response>110</response>
          <responseTime>2014-03-31T11:48:47</responseTime>
          <message>Insufficient Funds</message>
          <fraudResult>
            <avsResult>34</avsResult>
            <cardValidationResult>P</cardValidationResult>
          </fraudResult>
        </saleResponse>
      </litleOnlineResponse>
    )
  end
end
