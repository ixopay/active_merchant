require 'test_helper'

class BarclaysEpdqTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = BarclaysEpdqGateway.new(
      login: 'test_user',
      password: 'test_pass',
      client_id: '1234'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      order_id: 'order123',
      billing_address: address
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    response = @gateway.purchase(@amount, @credit_card, @options)

    assert_success response
    assert response.test?
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)
    response = @gateway.capture(@amount, 'order123', @options)

    assert_success response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)
    response = @gateway.refund(@amount, 'order123:txn456', @options)

    assert_success response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_void_response)
    response = @gateway.void('order123', @options)

    assert_success response
  end

  def test_authorize_sends_xml_with_preauth
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<Type>PreAuth</Type>), data
      assert_match %r(<Number>4111111111111111</Number>), data
      assert_match %r(<Name>test_user</Name>), data
    end.respond_with(successful_authorize_response)
  end

  def test_purchase_sends_xml_with_auth
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<Type>Auth</Type>), data
    end.respond_with(successful_purchase_response)
  end

  def test_capture_sends_xml_with_postauth
    stub_comms do
      @gateway.capture(@amount, 'order123', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<Type>PostAuth</Type>), data
      assert_match %r(<Id>order123</Id>), data
    end.respond_with(successful_capture_response)
  end

  def test_void_sends_xml_with_void_type
    stub_comms do
      @gateway.void('order123', @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<Type>Void</Type>), data
      assert_match %r(<Id>order123</Id>), data
    end.respond_with(successful_void_response)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = '<Number>4111111111111111</Number><Cvv2Val>123</Cvv2Val><Password>secret</Password>'
    scrubbed = @gateway.scrub(transcript)

    assert_match %r(<Number>\[FILTERED\]</Number>), scrubbed
    assert_match %r(<Cvv2Val>\[FILTERED\]</Cvv2Val>), scrubbed
    assert_match %r(<Password>\[FILTERED\]</Password>), scrubbed
    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/secret/, scrubbed)
  end

  def test_test_url_used_in_test_mode
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |endpoint, _data, _headers|
      assert_match %r(secure2\.mde\.epdq\.co\.uk), endpoint
    end.respond_with(successful_authorize_response)
  end

  private

  def successful_authorize_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <EngineDocList>
        <EngineDoc>
          <OrderFormDoc>
            <Id>order123</Id>
            <Transaction>
              <Id>txn456</Id>
              <Type>PreAuth</Type>
              <AuthCode>AB1234</AuthCode>
              <AvsRespCode>Y</AvsRespCode>
              <Cvv2Resp>M</Cvv2Resp>
              <CardProcResp>
                <CcReturnMsg>Approved.</CcReturnMsg>
              </CardProcResp>
            </Transaction>
          </OrderFormDoc>
        </EngineDoc>
      </EngineDocList>
    XML
  end

  def failed_authorize_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <EngineDocList>
        <EngineDoc>
          <OrderFormDoc>
            <Id>order123</Id>
            <Transaction>
              <Id>txn456</Id>
              <Type>PreAuth</Type>
              <CardProcResp>
                <CcReturnMsg>Declined.</CcReturnMsg>
              </CardProcResp>
            </Transaction>
            <Message>
              <Text>Transaction declined</Text>
            </Message>
          </OrderFormDoc>
        </EngineDoc>
      </EngineDocList>
    XML
  end

  def successful_purchase_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <EngineDocList>
        <EngineDoc>
          <OrderFormDoc>
            <Id>order123</Id>
            <Transaction>
              <Id>txn789</Id>
              <Type>Auth</Type>
              <AuthCode>CD5678</AuthCode>
              <AvsRespCode>Y</AvsRespCode>
              <Cvv2Resp>M</Cvv2Resp>
              <CardProcResp>
                <CcReturnMsg>Approved.</CcReturnMsg>
              </CardProcResp>
            </Transaction>
          </OrderFormDoc>
        </EngineDoc>
      </EngineDocList>
    XML
  end

  def successful_capture_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <EngineDocList>
        <EngineDoc>
          <OrderFormDoc>
            <Id>order123</Id>
            <Transaction>
              <Id>txn101</Id>
              <Type>PostAuth</Type>
              <AuthCode>EF9012</AuthCode>
              <CardProcResp>
                <CcReturnMsg>Approved.</CcReturnMsg>
              </CardProcResp>
            </Transaction>
          </OrderFormDoc>
        </EngineDoc>
      </EngineDocList>
    XML
  end

  def successful_refund_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <EngineDocList>
        <EngineDoc>
          <OrderFormDoc>
            <Id>order123</Id>
            <Transaction>
              <Id>txn201</Id>
              <Type>Credit</Type>
              <CardProcResp>
                <CcReturnMsg>Approved.</CcReturnMsg>
              </CardProcResp>
            </Transaction>
          </OrderFormDoc>
        </EngineDoc>
      </EngineDocList>
    XML
  end

  def successful_void_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <EngineDocList>
        <EngineDoc>
          <OrderFormDoc>
            <Id>order123</Id>
            <Transaction>
              <Id>txn301</Id>
              <Type>Void</Type>
              <CardProcResp>
                <CcReturnMsg>Approved.</CcReturnMsg>
              </CardProcResp>
            </Transaction>
          </OrderFormDoc>
        </EngineDoc>
      </EngineDocList>
    XML
  end
end
