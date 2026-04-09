require 'test_helper'

class IsbankTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = IsbankGateway.new(fixtures(:isbank))
    @credit_card = credit_card
    @amount = 100
    @options = {
      order_id: 'ORDER001'
    }
  end

  def test_live_url
    assert_equal 'https://sanalpos.isbank.com.tr/fim/api', IsbankGateway.live_url
  end

  def test_test_url
    assert_equal 'https://entegrasyon.asseco-see.com.tr/fim/api', IsbankGateway.test_url
  end

  def test_display_name
    assert_equal 'Isbank', IsbankGateway.display_name
  end

  def test_default_currency
    assert_equal 'TRY', IsbankGateway.default_currency
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end

  private

  def successful_purchase_response
    '<CC5Response><OrderId>ORDER001</OrderId><GroupId>ORDER001</GroupId><Response>Approved</Response><AuthCode>123456</AuthCode><ProcReturnCode>00</ProcReturnCode><ErrMsg></ErrMsg></CC5Response>'
  end

  def failed_purchase_response
    '<CC5Response><OrderId>ORDER001</OrderId><GroupId>ORDER001</GroupId><Response>Declined</Response><AuthCode></AuthCode><ProcReturnCode>05</ProcReturnCode><ErrMsg>General rejection</ErrMsg></CC5Response>'
  end
end
