require 'test_helper'

class PesoPayTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = PesoPayGateway.new(
      merchant_id: 'test_merchant'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345'
    }
  end

  def test_inherits_from_pay_dollar
    assert_equal PayDollarGateway, PesoPayGateway.superclass
  end

  def test_display_name
    assert_equal 'PesoPay', PesoPayGateway.display_name
  end

  def test_homepage_url
    assert_equal 'http://www.pesopay.com/', PesoPayGateway.homepage_url
  end
end
