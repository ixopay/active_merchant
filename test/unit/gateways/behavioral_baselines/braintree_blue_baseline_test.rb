require 'test_helper'

class BraintreeBlueBaselineTest < Test::Unit::TestCase
  include CommStub

  def setup
    @old_verbose, $VERBOSE = $VERBOSE, false

    @gateway = BraintreeBlueGateway.new(
      merchant_id: 'test',
      public_key: 'test',
      private_key: 'test',
      test: true
    )

    @internal_gateway = @gateway.instance_variable_get(:@braintree_gateway)
    @amount = 100
    @credit_card = credit_card('4111111111111111')
  end

  def teardown
    $VERBOSE = @old_verbose
  end

  def test_purchase_request_structure
    Braintree::TransactionGateway.any_instance.expects(:sale).
      with(has_entries(
        amount: '1.00',
        options: has_entries(submit_for_settlement: true)
      )).
      returns(braintree_result)

    response = @gateway.purchase(@amount, @credit_card)
    assert_success response
    assert_equal 'transaction_id', response.authorization
  end

  def test_authorize_request_structure
    Braintree::TransactionGateway.any_instance.expects(:sale).
      returns(braintree_result)

    response = @gateway.authorize(@amount, @credit_card)
    assert_success response
    assert_equal 'transaction_id', response.authorization
  end

  def test_successful_response_parsing
    Braintree::TransactionGateway.any_instance.expects(:sale).
      returns(braintree_result)

    response = @gateway.purchase(@amount, @credit_card)
    assert_success response
    assert_equal 'transaction_id', response.authorization
    assert_equal true, response.test
  end

  def test_failed_response_parsing
    Braintree::TransactionGateway.any_instance.expects(:sale).
      returns(braintree_error_result)

    response = @gateway.purchase(@amount, @credit_card)
    assert_failure response
  end

  def test_avs_cvv_result_parsing
    Braintree::TransactionGateway.any_instance.expects(:sale).
      returns(braintree_result(avs_postal_code_response_code: 'M', avs_street_address_response_code: 'M', cvv_response_code: 'M'))

    response = @gateway.purchase(@amount, @credit_card)
    assert_success response
    assert_equal 'M', response.cvv_result['code']
  end

  def test_supported_countries
    countries = BraintreeBlueGateway.supported_countries
    assert_includes countries, 'US'
    assert_includes countries, 'CA'
    assert countries.length > 5
  end

  def test_supported_card_types
    assert_equal %i[visa master american_express discover jcb diners_club maestro], BraintreeBlueGateway.supported_cardtypes
  end

  def test_gateway_display_name
    assert_equal 'Braintree (Blue Platform)', BraintreeBlueGateway.display_name
  end

  private

  def braintree_result(options = {})
    Braintree::SuccessfulResult.new(
      transaction: Braintree::Transaction._new(
        @internal_gateway,
        id: options[:id] || 'transaction_id',
        status: 'authorized',
        credit_card_details: Braintree::Transaction::CreditCardDetails.new(
          token: 'token',
          bin: '411111',
          last_4: '1111',
          card_type: 'Visa',
          expiration_month: '09',
          expiration_year: '2025'
        ),
        avs_postal_code_response_code: options[:avs_postal_code_response_code] || 'I',
        avs_street_address_response_code: options[:avs_street_address_response_code] || 'I',
        cvv_response_code: options[:cvv_response_code] || 'I',
        processor_response_code: '1000',
        processor_response_text: 'Approved'
      )
    )
  end

  def braintree_error_result(options = {})
    Braintree::ErrorResult.new(
      @internal_gateway,
      params: {},
      errors: { errors: [{ attribute: 'base', code: 91507, message: 'Cannot submit for settlement.' }] },
      message: 'Cannot submit for settlement.'
    )
  end
end
