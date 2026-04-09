require 'test_helper'

class WorldpayBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = WorldpayGateway.new(login: 'testlogin', password: 'testpassword')
    @amount = 100
    @credit_card = credit_card('4242424242424242')
    @options = { order_id: 1 }
  end

  def test_purchase_request_structure
    request_count = 0
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, headers|
      request_count += 1
      if request_count == 1
        assert_match(/<paymentService/, data)
        assert_match(/<submit>/, data)
        assert_match(/<order orderCode/, data)
        assert_match(/4242424242424242/, data)
        assert_match(/<amount value="100"/, data)
        assert_equal 'Basic dGVzdGxvZ2luOnRlc3RwYXNzd29yZA==', headers['Authorization']
      else
        assert_match(/<capture>/, data)
      end
    end.respond_with(successful_authorize_response, successful_authorize_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match(/<paymentService/, data)
      assert_match(/<order orderCode/, data)
      assert_match(/4242424242424242/, data)
      assert_match(/<amount value="100"/, data)
    end.respond_with(successful_authorize_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_success response
    assert_equal 'R50704213207145707', response.authorization
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(failed_authorize_response)

    assert_failure response
    assert_match(/Invalid payment details/, response.message)
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_success response
    # Worldpay returns description-based AVS/CVV results
    assert_not_nil response.avs_result
  end

  def test_supported_countries
    countries = WorldpayGateway.supported_countries
    assert_includes countries, 'US'
    assert_includes countries, 'GB'
    assert countries.length > 100
  end

  def test_supported_card_types
    card_types = WorldpayGateway.supported_cardtypes
    assert_includes card_types, :visa
    assert_includes card_types, :master
    assert_includes card_types, :american_express
    assert_includes card_types, :discover
    assert_includes card_types, :jcb
  end

  def test_gateway_display_name
    assert_equal 'Worldpay Global', WorldpayGateway.display_name
  end

  private

  def successful_authorize_response
    <<~RESPONSE
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE paymentService PUBLIC "-//Bibit//DTD Bibit PaymentService v1//EN"
                                      "http://dtd.bibit.com/paymentService_v1.dtd">
      <paymentService version="1.4" merchantCode="XXXXXXXXXXXXXXX">
        <reply>
          <orderStatus orderCode="R50704213207145707">
            <payment>
              <paymentMethod>VISA-SSL</paymentMethod>
              <amount value="15000" currencyCode="HKD" exponent="2" debitCreditIndicator="credit"/>
              <lastEvent>AUTHORISED</lastEvent>
              <CVCResultCode description="UNKNOWN"/>
              <AVSResultCode description="UNKNOWN"/>
              <balance accountType="IN_PROCESS_AUTHORISED">
                <amount value="15000" currencyCode="HKD" exponent="2" debitCreditIndicator="credit"/>
              </balance>
              <cardNumber>4111********1111</cardNumber>
              <riskScore value="1"/>
            </payment>
          </orderStatus>
        </reply>
      </paymentService>
    RESPONSE
  end

  def failed_authorize_response
    <<~RESPONSE
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE paymentService PUBLIC "-//Bibit//DTD Bibit PaymentService v1//EN"
                                      "http://dtd.bibit.com/paymentService_v1.dtd">
      <paymentService version="1.4" merchantCode="XXXXXXXXXXXXXXX">
        <reply>
          <orderStatus orderCode="R12538568107150952">
            <error code="7">
              <![CDATA[Invalid payment details : Card number : 4111********1111]]>
            </error>
          </orderStatus>
        </reply>
      </paymentService>
    RESPONSE
  end
end
