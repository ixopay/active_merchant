require 'test_helper'

class FirstdataE4BaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = FirstdataE4Gateway.new(
      login: 'A00427-01',
      password: 'testus'
    )
    @amount = 100
    @credit_card = credit_card
    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
    @authorization = 'ET1700;106625152;4738'
  end

  def test_purchase_request_structure
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<Transaction_Type>00</Transaction_Type>', data
      assert_match '<DollarAmount>1.00</DollarAmount>', data
      assert_match '<Card_Number>4242424242424242</Card_Number>', data
      assert_match '<Reference_No>1</Reference_No>', data
    end.respond_with(successful_purchase_response)
  end

  def test_authorize_request_structure
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<Transaction_Type>01</Transaction_Type>', data
      assert_match '<DollarAmount>1.00</DollarAmount>', data
      assert_match '<Card_Number>4242424242424242</Card_Number>', data
    end.respond_with(successful_purchase_response)
  end

  def test_capture_request_structure
    stub_comms do
      @gateway.capture(@amount, @authorization)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<Transaction_Type>32</Transaction_Type>', data
      assert_match '<DollarAmount>1.00</DollarAmount>', data
      assert_match '<Authorization_Num>ET1700</Authorization_Num>', data
      assert_match '<Transaction_Tag>106625152</Transaction_Tag>', data
    end.respond_with(successful_purchase_response)
  end

  def test_refund_request_structure
    stub_comms do
      @gateway.refund(@amount, @authorization)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<Transaction_Type>34</Transaction_Type>', data
      assert_match '<DollarAmount>1.00</DollarAmount>', data
      assert_match '<Transaction_Tag>106625152</Transaction_Tag>', data
    end.respond_with(successful_refund_response)
  end

  def test_void_request_structure
    stub_comms do
      @gateway.void(@authorization)
    end.check_request do |_endpoint, data, _headers|
      assert_match '<Transaction_Type>33</Transaction_Type>', data
      assert_match '<Authorization_Num>ET1700</Authorization_Num>', data
      assert_match '<Transaction_Tag>106625152</Transaction_Tag>', data
    end.respond_with(successful_void_response)
  end

  def test_successful_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_success response
    assert_equal 'ET1700;106625152;4738', response.authorization
    assert_equal 'Transaction Normal - Approved', response.message
    assert_equal 'true', response.params['transaction_approved']
    assert_equal '100', response.params['bank_resp_code']
  end

  def test_failed_response_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(failed_purchase_response)

    assert_failure response
    assert_equal 'Transaction Normal - Invalid Expiration Date', response.message
    assert_equal 'false', response.params['transaction_approved']
    assert_equal '605', response.params['bank_resp_code']
  end

  def test_avs_cvv_result_parsing
    response = stub_comms do
      @gateway.purchase(@amount, @credit_card, @options)
    end.respond_with(successful_purchase_response)

    assert_equal 'U', response.avs_result['code']
    assert_equal 'M', response.cvv_result['code']
  end

  private

  def successful_purchase_response
    <<~RESPONSE
      <?xml version="1.0" encoding="UTF-8"?>
      <TransactionResult>
        <ExactID>AD1234-56</ExactID>
        <Password></Password>
        <Transaction_Type>00</Transaction_Type>
        <DollarAmount>47.38</DollarAmount>
        <SurchargeAmount></SurchargeAmount>
        <Card_Number>############1111</Card_Number>
        <Transaction_Tag>106625152</Transaction_Tag>
        <Authorization_Num>ET1700</Authorization_Num>
        <Expiry_Date>0913</Expiry_Date>
        <CardHoldersName>Fred Burfle</CardHoldersName>
        <Reference_No>77</Reference_No>
        <Transaction_Error>false</Transaction_Error>
        <Transaction_Approved>true</Transaction_Approved>
        <EXact_Resp_Code>00</EXact_Resp_Code>
        <EXact_Message>Transaction Normal</EXact_Message>
        <Bank_Resp_Code>100</Bank_Resp_Code>
        <Bank_Message>Approved</Bank_Message>
        <SequenceNo>000040</SequenceNo>
        <AVS>U</AVS>
        <CVV2>M</CVV2>
        <Retrieval_Ref_No>3146117</Retrieval_Ref_No>
        <Currency>USD</Currency>
        <PartialRedemption>false</PartialRedemption>
        <TransarmorToken>8938737759041111</TransarmorToken>
        <CTR>=========== TRANSACTION RECORD ==========</CTR>
      </TransactionResult>
    RESPONSE
  end

  def successful_refund_response
    <<~RESPONSE
      <?xml version="1.0" encoding="UTF-8"?>
      <TransactionResult>
        <ExactID>AD1234-56</ExactID>
        <Transaction_Type>34</Transaction_Type>
        <DollarAmount>123</DollarAmount>
        <Card_Number>############1111</Card_Number>
        <Transaction_Tag>888</Transaction_Tag>
        <Authorization_Num>ET112216</Authorization_Num>
        <Transaction_Error>false</Transaction_Error>
        <Transaction_Approved>true</Transaction_Approved>
        <EXact_Resp_Code>00</EXact_Resp_Code>
        <EXact_Message>Transaction Normal</EXact_Message>
        <Bank_Resp_Code>100</Bank_Resp_Code>
        <Bank_Message>Approved</Bank_Message>
        <AVS></AVS>
        <CVV2>I</CVV2>
        <Currency>USD</Currency>
        <PartialRedemption>false</PartialRedemption>
      </TransactionResult>
    RESPONSE
  end

  def successful_void_response
    <<~RESPONSE
      <?xml version="1.0" encoding="UTF-8"?>
      <TransactionResult>
        <ExactID>AD1234-56</ExactID>
        <Transaction_Type>33</Transaction_Type>
        <DollarAmount>47.38</DollarAmount>
        <Card_Number>############1111</Card_Number>
        <Transaction_Tag>106625152</Transaction_Tag>
        <Authorization_Num>ET1700</Authorization_Num>
        <Transaction_Error>false</Transaction_Error>
        <Transaction_Approved>true</Transaction_Approved>
        <EXact_Resp_Code>00</EXact_Resp_Code>
        <EXact_Message>Transaction Normal</EXact_Message>
        <Bank_Resp_Code>100</Bank_Resp_Code>
        <Bank_Message>Approved</Bank_Message>
        <AVS></AVS>
        <CVV2></CVV2>
        <Currency>USD</Currency>
        <PartialRedemption>false</PartialRedemption>
      </TransactionResult>
    RESPONSE
  end

  def failed_purchase_response
    <<~RESPONSE
      <?xml version="1.0" encoding="UTF-8"?>
      <TransactionResult>
        <ExactID>AD1234-56</ExactID>
        <Transaction_Type>00</Transaction_Type>
        <DollarAmount>5013.0</DollarAmount>
        <Card_Number>############1111</Card_Number>
        <Transaction_Tag>555555</Transaction_Tag>
        <Authorization_Num></Authorization_Num>
        <Transaction_Error>false</Transaction_Error>
        <Transaction_Approved>false</Transaction_Approved>
        <EXact_Resp_Code>00</EXact_Resp_Code>
        <EXact_Message>Transaction Normal</EXact_Message>
        <Bank_Resp_Code>605</Bank_Resp_Code>
        <Bank_Message>Invalid Expiration Date</Bank_Message>
        <AVS></AVS>
        <CVV2></CVV2>
        <Currency>USD</Currency>
        <PartialRedemption>false</PartialRedemption>
      </TransactionResult>
    RESPONSE
  end
end
