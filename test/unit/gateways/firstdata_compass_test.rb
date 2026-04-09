require 'test_helper'

class FirstdataCompassTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = FirstdataCompassGateway.new(login: 'test_user', password: 'test_pass')
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      billing_address: address,
      order_id: '12345',
      division_id: '001'
    }
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert_equal 'Approved', response.message
    assert_equal 'ABC123;20240101', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
    assert_equal 'Processor Decline', response.message
    assert_nil response.authorization
    assert_equal 'card_declined', response.error_code
  end

  def test_verify_action_for_zero_amount
    stub_comms do
      @gateway.authorize(0, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:ActionCode>VF</cmpmsg:ActionCode>), data
    end.respond_with(successful_authorize_response)
  end

  def test_authorize_action_for_nonzero
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:ActionCode>AU</cmpmsg:ActionCode>), data
    end.respond_with(successful_authorize_response)
  end

  def test_successful_reverse
    authorization = 'ABC123;20240101'

    stub_comms do
      @gateway.reverse(@amount, authorization, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:ActionCode>AR</cmpmsg:ActionCode>), data
      assert_match %r(<cmpmsg:AuthorizationCode>ABC123</cmpmsg:AuthorizationCode>), data
      assert_match %r(<cmpmsg:ResponseDate>20240101</cmpmsg:ResponseDate>), data
    end.respond_with(successful_reverse_response)
  end

  def test_reverse_requires_authorization
    assert_raise ArgumentError do
      @gateway.reverse(@amount, nil, @credit_card, @options)
    end

    assert_raise ArgumentError do
      @gateway.reverse(@amount, '', @credit_card, @options)
    end
  end

  def test_soap_envelope_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cmp="http://firstdata.com/cmpwsapi/schemas/cmpapi"), data
      assert_match %r(<soapenv:Header/>), data
      assert_match %r(<soapenv:Body>), data
      assert_match %r(<cmpapi:OnlineTransRequest xmlns:cmpapi="http://firstdata.com/cmpwsapi/schemas/cmpapi" xmlns:cmpmsg="http://firstdata.com/cmpwsapi/schemas/cmpmsg"), data
      assert_match %r(<cmpapi:Transaction>), data
      assert_match %r(<cmpapi:AdditionalFormats>), data
    end.respond_with(successful_authorize_response)
  end

  def test_credit_card_code_mapping
    expected = {
      american_express: 'AX',
      diners_club: 'DC',
      discover: 'DI',
      jcb: 'JC',
      master: 'MC',
      maestro: 'MI',
      visa: 'VI'
    }

    expected.each do |brand, code|
      assert_equal code, FirstdataCompassGateway::CREDIT_CARD_CODES[brand]
    end
  end

  def test_visa_card_sends_vi_code
    stub_comms do
      @gateway.authorize(@amount, credit_card('4111111111111111', brand: 'visa'), @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:Mop>VI</cmpmsg:Mop>), data
    end.respond_with(successful_authorize_response)
  end

  def test_mastercard_sends_mc_code
    stub_comms do
      @gateway.authorize(@amount, credit_card('5500000000000004', brand: 'master'), @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:Mop>MC</cmpmsg:Mop>), data
    end.respond_with(successful_authorize_response)
  end

  def test_avs_code_translation
    expected_translations = {
      'IG' => 'E', 'IU' => 'E', 'ID' => 'S', 'IE' => 'E',
      'IS' => 'R', 'IA' => 'D', 'IB' => 'B', 'IC' => 'C',
      'IP' => 'P', 'A3' => 'V', 'B3' => 'H', 'B4' => 'F',
      'B7' => 'T', '??' => 'R', 'I1' => 'M', 'I2' => 'W',
      'I3' => 'Y', 'I4' => 'Z', 'I5' => 'X', 'I6' => 'W',
      'I7' => 'A', 'I8' => 'N'
    }

    expected_translations.each do |compass_code, standard_code|
      assert_equal standard_code, FirstdataCompassGateway::AVS_CODE_TRANSLATOR[compass_code],
        "AVS code #{compass_code} should translate to #{standard_code}"
    end
  end

  def test_avs_result_from_response
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_equal 'Y', response.avs_result['code']
  end

  def test_cvv_result_from_response
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_equal 'M', response.cvv_result['code']
  end

  def test_response_code_mapping
    codes = FirstdataCompassGateway::RESPONSE_CODES

    assert_equal 'No Answer', codes[:r000]
    assert_equal 'Approved', codes[:r100]
    assert_equal 'Validated', codes[:r101]
    assert_equal 'Verified', codes[:r102]
    assert_equal 'Suspected Fraud', codes[:r200]
    assert_equal 'Invalid CC Number', codes[:r201]
    assert_equal 'Processor Decline', codes[:r303]
    assert_equal 'Insufficient funds', codes[:r521]
    assert_equal 'Card is expired', codes[:r522]
    assert_equal 'Do Not Honor', codes[:r530]
    assert_equal 'CVV2/VAK Failure', codes[:r531]
    assert_equal 'Invalid Security Code', codes[:r811]
  end

  def test_expdate_format
    card = credit_card('4111111111111111', month: 3, year: 2025)

    stub_comms do
      @gateway.authorize(@amount, card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:ExpirationDate>0325</cmpmsg:ExpirationDate>), data
    end.respond_with(successful_authorize_response)
  end

  def test_expdate_format_double_digit_month
    card = credit_card('4111111111111111', month: 12, year: 2026)

    stub_comms do
      @gateway.authorize(@amount, card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:ExpirationDate>1226</cmpmsg:ExpirationDate>), data
    end.respond_with(successful_authorize_response)
  end

  def test_address_handling
    options_with_addresses = @options.merge(
      billing_address: {
        name: 'Jim Smith',
        address1: '456 My Street',
        address2: 'Apt 1',
        city: 'Ottawa',
        state: 'ON',
        zip: 'K1C2N6',
        country: 'CA',
        phone: '(555)555-5555'
      },
      shipping_address: {
        name: 'Jane Doe',
        address1: '789 Her Street',
        city: 'Toronto',
        state: 'ON',
        zip: 'M5V2T6',
        country: 'CA',
        phone: '(555)555-6666'
      }
    )

    stub_comms do
      @gateway.authorize(@amount, @credit_card, options_with_addresses)
    end.check_request do |_endpoint, data, _headers|
      # Billing address (AB)
      assert_match %r(<cmpmsg:AB>), data
      assert_match %r(<cmpmsg:NameText>Jim Smith</cmpmsg:NameText>), data
      assert_match %r(<cmpmsg:Address1>456 My Street</cmpmsg:Address1>), data
      assert_match %r(<cmpmsg:Address2>Apt 1</cmpmsg:Address2>), data
      assert_match %r(<cmpmsg:City>Ottawa</cmpmsg:City>), data
      assert_match %r(<cmpmsg:State>ON</cmpmsg:State>), data
      assert_match %r(<cmpmsg:PostalCode>K1C2N6</cmpmsg:PostalCode>), data
      assert_match %r(<cmpmsg:CountryCode>CA</cmpmsg:CountryCode>), data

      # Shipping address (AS)
      assert_match %r(<cmpmsg:AS>), data
      assert_match %r(<cmpmsg:NameText>Jane Doe</cmpmsg:NameText>), data
      assert_match %r(<cmpmsg:Address1>789 Her Street</cmpmsg:Address1>), data
    end.respond_with(successful_authorize_response)
  end

  def test_no_shipping_address_when_nil
    options_without_shipping = @options.dup
    options_without_shipping.delete(:shipping_address)

    stub_comms do
      @gateway.authorize(@amount, @credit_card, options_without_shipping)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:AB>), data
      assert_no_match %r(<cmpmsg:AS>), data
    end.respond_with(successful_authorize_response)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = pre_scrubbed
    scrubbed = @gateway.scrub(transcript)

    assert_equal post_scrubbed, scrubbed
    assert_match %r(\[FILTERED\]), scrubbed
    assert_no_match %r(4111111111111111), scrubbed
    assert_no_match %r(123<), scrubbed
    assert_no_match %r(Basic dGVzdF91c2VyOnRlc3RfcGFzcw==), scrubbed
  end

  def test_unsupported_card_brand_raises_error
    bad_card = credit_card('4111111111111111', brand: 'bogus')

    assert_raise ArgumentError do
      @gateway.authorize(@amount, bad_card, @options)
    end
  end

  def test_missing_credit_card_raises_error
    assert_raise ArgumentError do
      @gateway.authorize(@amount, nil, @options)
    end
  end

  def test_fraud_review
    @gateway.expects(:ssl_post).returns(fraud_review_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
    assert response.fraud_review?
    assert_equal 'Suspected Fraud', response.message
  end

  def test_non_fraud_response_not_fraud_review
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert !response.fraud_review?
  end

  def test_order_id_in_request
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:OrderNumber>12345</cmpmsg:OrderNumber>), data
    end.respond_with(successful_authorize_response)
  end

  def test_division_id_in_request
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:DivisionNumber>001</cmpmsg:DivisionNumber>), data
    end.respond_with(successful_authorize_response)
  end

  def test_amount_in_request
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:Amount>100</cmpmsg:Amount>), data
    end.respond_with(successful_authorize_response)
  end

  def test_default_transaction_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:TransactionType>7</cmpmsg:TransactionType>), data
      assert_match %r(<cmpmsg:BillPaymentIndicator>N</cmpmsg:BillPaymentIndicator>), data
    end.respond_with(successful_authorize_response)
  end

  def test_custom_transaction_type
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options.merge(moto_ecommerce_ind: '2'))
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:TransactionType>2</cmpmsg:TransactionType>), data
    end.respond_with(successful_authorize_response)
  end

  def test_payment_details_with_name_and_cvv
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:LN>), data
      assert_match %r(<cmpmsg:FirstName>Longbob</cmpmsg:FirstName>), data
      assert_match %r(<cmpmsg:LastName>Longsen</cmpmsg:LastName>), data
      assert_match %r(<cmpmsg:FR>), data
      assert_match %r(<cmpmsg:CardSecurityValue>123</cmpmsg:CardSecurityValue>), data
      assert_match %r(<cmpmsg:CardSecurityPresence>1</cmpmsg:CardSecurityPresence>), data
    end.respond_with(successful_authorize_response)
  end

  def test_customer_ip_in_request
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options.merge(ip: '192.168.1.1'))
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:AI>), data
      assert_match %r(<cmpmsg:CustomerIPAddress>192.168.1.1</cmpmsg:CustomerIPAddress>), data
    end.respond_with(successful_authorize_response)
  end

  def test_email_in_request
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options.merge(email: 'test@example.com'))
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:AL>), data
      assert_match %r(<cmpmsg:EmailAddress>test@example.com</cmpmsg:EmailAddress>), data
    end.respond_with(successful_authorize_response)
  end

  def test_authorization_header
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, _data, headers|
      expected_auth = 'Basic ' + Base64.strict_encode64('test_user:test_pass').chomp
      assert_equal expected_auth, headers['Authorization']
      assert_equal 'text/xml', headers['Content-Type']
    end.respond_with(successful_authorize_response)
  end

  def test_standard_error_code_mapping
    mapping = FirstdataCompassGateway::STANDARD_ERROR_CODE_MAPPING

    assert_equal Gateway::STANDARD_ERROR_CODE[:invalid_number], mapping['r201']
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], mapping['r303']
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], mapping['r521']
    assert_equal Gateway::STANDARD_ERROR_CODE[:expired_card], mapping['r522']
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], mapping['r530']
    assert_equal Gateway::STANDARD_ERROR_CODE[:incorrect_cvc], mapping['r531']
    assert_equal Gateway::STANDARD_ERROR_CODE[:invalid_number], mapping['r591']
    assert_equal Gateway::STANDARD_ERROR_CODE[:invalid_expiry_date], mapping['r605']
    assert_equal Gateway::STANDARD_ERROR_CODE[:incorrect_cvc], mapping['r811']
  end

  def test_soap_fault_response
    @gateway.expects(:ssl_post).returns(soap_fault_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
    assert_equal 'Server Error', response.message
  end

  def test_requires_login_and_password
    assert_raise ArgumentError do
      FirstdataCompassGateway.new
    end
  end

  def test_requires_order_id
    assert_raise ArgumentError do
      @gateway.authorize(@amount, @credit_card, { division_id: '001' })
    end
  end

  def test_requires_division_id
    assert_raise ArgumentError do
      @gateway.authorize(@amount, @credit_card, { order_id: '12345' })
    end
  end

  def test_supported_countries
    assert_equal %w[US CA], FirstdataCompassGateway.supported_countries
  end

  def test_supported_card_types
    assert_equal [:visa, :master, :american_express, :discover, :diners_club, :jcb], FirstdataCompassGateway.supported_cardtypes
  end

  def test_default_currency
    assert_equal '840', FirstdataCompassGateway.default_currency
  end

  def test_sensitive_fields_not_in_response
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    FirstdataCompassGateway::SENSITIVE_FIELDS.each do |field|
      assert !response.params.key?(field.to_s), "Sensitive field #{field} should be filtered from response"
    end
  end

  def test_credit_card_number_in_request
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match %r(<cmpmsg:AccountNumber>4111111111111111</cmpmsg:AccountNumber>), data
    end.respond_with(successful_authorize_response)
  end

  def test_nil_response_reason_code
    @gateway.expects(:ssl_post).returns(nil_response_code_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
  end

  private

  def pre_scrubbed
    <<~TRANSCRIPT
      opening connection to merchanttest.ctexmloma.compass-xml.com:443...
      <- "POST /cmpwsapi/services/order.wsdl HTTP/1.1\\r\\nAuthorization: Basic dGVzdF91c2VyOnRlc3RfcGFzcw==\\r\\nContent-Type: text/xml\\r\\n"
      <- "<cmpmsg:AccountNumber>4111111111111111</cmpmsg:AccountNumber><cmpmsg:ExpirationDate>0925</cmpmsg:ExpirationDate><cmpmsg:CardSecurityValue>123</cmpmsg:CardSecurityValue>"
    TRANSCRIPT
  end

  def post_scrubbed
    <<~TRANSCRIPT
      opening connection to merchanttest.ctexmloma.compass-xml.com:443...
      <- "POST /cmpwsapi/services/order.wsdl HTTP/1.1\\r\\nAuthorization: Basic [FILTERED]\\r\\nContent-Type: text/xml\\r\\n"
      <- "<cmpmsg:AccountNumber>[FILTERED]</cmpmsg:AccountNumber><cmpmsg:ExpirationDate>0925</cmpmsg:ExpirationDate><cmpmsg:CardSecurityValue>[FILTERED]</cmpmsg:CardSecurityValue>"
    TRANSCRIPT
  end

  def successful_authorize_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <ns3:OnlineTransResponse xmlns:ns3="http://firstdata.com/cmpwsapi/schemas/cmpapi">
            <ResponseReasonCode>100</ResponseReasonCode>
            <AuthorizationCode>ABC123</AuthorizationCode>
            <ResponseDate>20240101</ResponseDate>
            <AVSResponseCode>I3</AVSResponseCode>
            <CSVResponseCode>M</CSVResponseCode>
          </ns3:OnlineTransResponse>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
    XML
  end

  def failed_authorize_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <ns3:OnlineTransResponse xmlns:ns3="http://firstdata.com/cmpwsapi/schemas/cmpapi">
            <ResponseReasonCode>303</ResponseReasonCode>
            <AVSResponseCode>I8</AVSResponseCode>
            <CSVResponseCode>N</CSVResponseCode>
          </ns3:OnlineTransResponse>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
    XML
  end

  def successful_reverse_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <ns3:OnlineTransResponse xmlns:ns3="http://firstdata.com/cmpwsapi/schemas/cmpapi">
            <ResponseReasonCode>100</ResponseReasonCode>
            <AuthorizationCode>DEF456</AuthorizationCode>
            <ResponseDate>20240102</ResponseDate>
            <AVSResponseCode>I3</AVSResponseCode>
            <CSVResponseCode>M</CSVResponseCode>
          </ns3:OnlineTransResponse>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
    XML
  end

  def fraud_review_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <ns3:OnlineTransResponse xmlns:ns3="http://firstdata.com/cmpwsapi/schemas/cmpapi">
            <ResponseReasonCode>200</ResponseReasonCode>
            <AVSResponseCode>I3</AVSResponseCode>
            <CSVResponseCode>M</CSVResponseCode>
          </ns3:OnlineTransResponse>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
    XML
  end

  def soap_fault_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <SOAP-ENV:Fault>
            <faultcode>SOAP-ENV:Server</faultcode>
            <faultstring>Server Error</faultstring>
            <detail>
              <message>Internal processing error</message>
            </detail>
          </SOAP-ENV:Fault>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
    XML
  end

  def nil_response_code_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <ns3:OnlineTransResponse xmlns:ns3="http://firstdata.com/cmpwsapi/schemas/cmpapi">
          </ns3:OnlineTransResponse>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
    XML
  end
end
