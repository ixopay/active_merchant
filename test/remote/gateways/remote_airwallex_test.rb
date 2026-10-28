require 'test_helper'

class RemoteAirwallexTest < Test::Unit::TestCase
  def setup
    @gateway = AirwallexGateway.new(fixtures(:airwallex))

    # https://www.airwallex.com/docs/online-payments__test-card-numbers
    @amount = 100
    @declined_amount = 8014
    @credit_card = credit_card('4012 0003 0000 1003')
    @declined_card = credit_card('2223 0000 1018 1375')
    @amex_card = credit_card('3706 3680 3809 394', brand: 'american_express', verification_value: '1234')
    @amex_declined_amount = 8100
    @amex_declined_card = credit_card('3703 5368 7686 779', brand: 'american_express', verification_value: '1234')
    # Debit cards from https://www.airwallex.com/docs/payments/test-and-go-live/test-card-numbers
    @visa_debit_card = credit_card('4035 5010 0000 0008')
    @mastercard_debit_card = credit_card('5354 5631 3425 7854', brand: 'master')
    @options = { return_url: 'https://example.com', description: 'a test transaction' }
    @stored_credential_cit_options = { initial_transaction: true, initiator: 'cardholder', reason_type: 'recurring', network_transaction_id: nil }
    @stored_credential_mit_options = { initial_transaction: false, initiator: 'merchant', reason_type: 'recurring' }
  end

  def test_failed_access_token
    assert_raises(ActiveMerchant::OAuthResponseError) do
      gateway = AirwallexGateway.new({ client_id: 'YOUR_CLIENT_ID', client_api_key: 'YOUR_API_KEY' })
      gateway.send :setup_access_token
    end
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'AUTHORIZED', response.message
    assert_not_nil response.authorization
  end

  def test_successful_purchase_with_amex
    response = @gateway.purchase(@amount, @amex_card, @options)
    assert_success response
    assert_equal 'AUTHORIZED', response.message
    assert_not_nil response.authorization
  end

  def test_failed_purchase_with_amex
    response = @gateway.purchase(@amex_declined_amount, @amex_declined_card, @options)
    assert_failure response
  end

  def test_successful_authorize_and_capture_with_amex
    auth = @gateway.authorize(@amount, @amex_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization, @options)
    assert_success capture
    assert_equal 'CAPTURE_REQUESTED', capture.message
  end

  def test_successful_purchase_with_shipping_address
    response = @gateway.purchase(@amount, @credit_card, @options.merge(shipping_address: address))
    assert_success response
    assert_equal 'AUTHORIZED', response.message
  end

  def test_successful_purchase_with_order_products_and_shipping_address
    products = [
      {
        'category' => 'test',
        'code' => '12345',
        'desc' => 'product description',
        'effective_end_at' => '2025-02-01T10:30:00Z',
        'effective_start_at' => '2025-01-01T10:30:00Z',
        'image_url' => 'www.test.com',
        'name' => 'test name',
        'quantity' => 1,
        'seller' => {
          'identifier' => 'identity',
          'name' => 'name'
        },
        'sku' => '12345test',
        'type' => 'intangible_good',
        'unit_price' => 2,
        'url' => 'www.123test.com'
      }
    ]
    response = @gateway.purchase(@amount, @credit_card, @options.merge(shipping_address: address, products:))
    assert_success response
    assert_equal 'AUTHORIZED', response.message
    assert_not_nil response.params['order']['products']
    assert_not_nil response.authorization
  end

  def test_successful_purchase_with_order_products_without_shipping_address
    products = [
      {
        'category' => 'test',
        'code' => '12345',
        'desc' => 'product description',
        'effective_end_at' => '2025-02-01T10:30:00Z',
        'effective_start_at' => '2025-01-01T10:30:00Z',
        'image_url' => 'www.test.com',
        'name' => 'test name',
        'quantity' => 1,
        'seller' => {
          'identifier' => 'identity',
          'name' => 'name'
        },
        'sku' => '12345test',
        'type' => 'intangible_good',
        'unit_price' => 2,
        'url' => 'www.123test.com'
      }
    ]
    response = @gateway.purchase(@amount, @credit_card, @options.merge(products:))
    assert_success response
    assert_equal 'AUTHORIZED', response.message
    assert_not_nil response.params['order']['products']
    assert_not_nil response.authorization
  end

  def test_successful_purchase_with_address
    response = @gateway.purchase(@amount, @credit_card, @options.merge(address))
    assert_success response
    assert_equal 'AUTHORIZED', response.message
  end

  def test_successful_purchase_with_specified_ids
    request_id = SecureRandom.uuid
    merchant_order_id = SecureRandom.uuid
    response = @gateway.purchase(@amount, @credit_card, @options.merge(request_id:, merchant_order_id:))
    assert_success response
    assert_match(request_id, response.params.dig('request_id'))
    assert_match(merchant_order_id, response.params.dig('merchant_order_id'))
  end

  def test_successful_purchase_with_skip_3ds
    response = @gateway.purchase(@amount, @credit_card, @options.merge({ skip_3ds: 'true' }))
    assert_success response
    assert_equal 'AUTHORIZED', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(@declined_amount, @declined_card, @options)
    assert_failure response
    assert_equal 'Invalid Card Number', response.message
    assert_equal '14', response.error_code
  end

  def test_purchase_with_reused_id_fails
    options = @options.merge(request_id: SecureRandom.uuid)
    assert_success @gateway.purchase(@amount, @credit_card, options)

    response = @gateway.purchase(@amount, @credit_card, options)
    assert_failure response
    assert_not_nil response.error_code
  end

  def test_failed_purchase_with_insufficient_funds
    response = @gateway.purchase(8051, @declined_card, @options)
    assert_failure response
    assert_equal 'Insufficient Funds', response.message
    assert_equal '51', response.error_code
  end

  def test_failed_purchase_with_do_not_honor
    response = @gateway.purchase(8005, @declined_card, @options)
    assert_failure response
    assert_equal 'Do Not Honor', response.message
    assert_equal '05', response.error_code
  end

  def test_failed_purchase_without_cvv
    response = @gateway.purchase(@amount, credit_card('4012 0003 0000 1003', verification_value: nil), @options)
    assert_failure response
    assert_equal 'CVC is not present', response.message
    assert_equal 'validation_error', response.error_code
  end

  # ActiveMerchant amounts are always x100, so 100000 is JPY 1000 and is sent as "1000".
  # Fails with an Airwallex error (not an exception) if JPY isn't enabled on the account.
  def test_successful_purchase_with_jpy
    response = @gateway.purchase(100000, @credit_card, @options.merge(currency: 'JPY'))
    assert_success response, "JPY purchase failed: #{response.message} (#{response.error_code})"
    assert_equal 'JPY', response.params['currency']
    assert_equal 1000, response.params['amount']
  end

  def test_successful_authorize_and_full_capture_with_jpy
    auth = @gateway.authorize(100000, @credit_card, @options.merge(currency: 'JPY'))
    assert_success auth, "JPY authorize failed: #{auth.message} (#{auth.error_code})"

    capture = @gateway.capture(100000, auth.authorization, @options.merge(currency: 'JPY'))
    assert_success capture
    assert_equal 'CAPTURE_REQUESTED', capture.message
    assert_equal 1000, capture.params['captured_amount']
  end

  def test_successful_authorize_and_partial_capture_with_jpy
    auth = @gateway.authorize(100000, @credit_card, @options.merge(currency: 'JPY'))
    assert_success auth, "JPY authorize failed: #{auth.message} (#{auth.error_code})"

    capture = @gateway.capture(50000, auth.authorization, @options.merge(currency: 'JPY'))
    assert_success capture
    assert_equal 500, capture.params['captured_amount']
  end

  def test_successful_purchase_and_refund_with_jpy
    purchase = @gateway.purchase(100000, @credit_card, @options.merge(currency: 'JPY'))
    assert_success purchase, "JPY purchase failed: #{purchase.message} (#{purchase.error_code})"

    refund = @gateway.refund(100000, purchase.authorization, @options.merge(currency: 'JPY'))
    assert_success refund
    assert_equal 'RECEIVED', refund.message
    assert_equal 'JPY', refund.params['currency']
    assert_equal 1000, refund.params['amount']
  end

  def test_successful_purchase_and_partial_refund_with_jpy
    purchase = @gateway.purchase(100000, @credit_card, @options.merge(currency: 'JPY'))
    assert_success purchase, "JPY purchase failed: #{purchase.message} (#{purchase.error_code})"

    refund = @gateway.refund(40000, purchase.authorization, @options.merge(currency: 'JPY'))
    assert_success refund
    assert_equal 400, refund.params['amount']
  end

  def test_successful_purchase_with_name_only_on_billing_address
    card = credit_card('4012 0003 0000 1003', first_name: nil, last_name: nil)
    billing_address = address(name: 'Jane Doe', email: 'jane@example.com', phone: '5555555555')

    response = @gateway.purchase(@amount, card, @options.merge(billing_address:))
    assert_success response
    billing = response.params.dig('latest_payment_attempt', 'payment_method', 'card', 'billing')
    assert_equal 'Jane', billing['first_name']
    assert_equal 'Doe', billing['last_name']
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization, @options)
    assert_success capture
    assert_equal 'CAPTURE_REQUESTED', capture.message
  end

  def test_failed_authorize
    response = @gateway.authorize(@declined_amount, @declined_card, @options)
    assert_failure response
    assert_equal 'Invalid Card Number', response.message
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization, @options)
    assert_success capture
  end

  def test_failed_capture
    response = @gateway.capture(@declined_amount, '12345', @options)
    assert_failure response
    assert_match(/The requested endpoint does not exist/, response.message)
  end

  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, purchase.authorization, @options)
    assert_success refund
    assert_equal 'RECEIVED', refund.message
    assert_not_nil refund.authorization
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount - 1, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    response = @gateway.refund(@declined_amount, '12345', @options)
    assert_failure response
    assert_match(/The PaymentIntent with ID 12345 cannot be found./, response.message)
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization, @options)
    assert_success void
    assert_equal 'CANCELLED', void.message
  end

  def test_failed_void
    response = @gateway.void('12345', @options)
    assert_failure response
    assert_match(/The requested endpoint does not exist/, response.message)
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{AUTHORIZED}, response.message
  end

  def test_failed_verify
    response = @gateway.verify(credit_card('1111111111111111'), @options)
    assert_failure response
    assert_match %r{Invalid card number}, response.message
  end

  def test_descriptor_is_truncated_to_max_length
    response = @gateway.verify(@credit_card, @options.merge(description: 'This description is longer than 32 characters.'))
    assert_success response
    assert_match %r{AUTHORIZED}, response.message
  end

  def test_successful_cit_with_recurring_stored_credential
    auth = @gateway.authorize(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success auth
  end

  def test_successful_mit_with_recurring_stored_credential
    auth = @gateway.authorize(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success auth

    add_cit_network_transaction_id_to_stored_credential(auth)

    purchase = @gateway.purchase(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_mit_options))
    assert_success purchase
  end

  def test_successful_mit_with_unscheduled_stored_credential
    @stored_credential_cit_options[:reason_type] = 'unscheduled'
    @stored_credential_mit_options[:reason_type] = 'unscheduled'

    auth = @gateway.authorize(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success auth

    add_cit_network_transaction_id_to_stored_credential(auth)

    purchase = @gateway.purchase(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_mit_options))
    assert_success purchase
  end

  def test_successful_mit_with_installment_stored_credential
    @stored_credential_cit_options[:reason_type] = 'installment'
    @stored_credential_mit_options[:reason_type] = 'installment'

    auth = @gateway.authorize(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success auth

    add_cit_network_transaction_id_to_stored_credential(auth)

    purchase = @gateway.purchase(@amount, @credit_card, @options.merge(stored_credential: @stored_credential_mit_options))
    assert_success purchase
  end

  def test_successful_cit_then_mit_with_visa_debit
    assert_successful_debit_cit_then_mit(@visa_debit_card)
  end

  def test_successful_cit_then_mit_with_mastercard_debit
    assert_successful_debit_cit_then_mit(@mastercard_debit_card)
  end

  def test_successful_cit_then_unscheduled_mit_with_visa_debit
    @stored_credential_cit_options[:reason_type] = 'unscheduled'
    @stored_credential_mit_options[:reason_type] = 'unscheduled'

    assert_successful_debit_cit_then_mit(@visa_debit_card)
  end

  def test_successful_cit_then_unscheduled_mit_with_mastercard_debit
    @stored_credential_cit_options[:reason_type] = 'unscheduled'
    @stored_credential_mit_options[:reason_type] = 'unscheduled'

    assert_successful_debit_cit_then_mit(@mastercard_debit_card)
  end

  # In test mode Airwallex only provides test network transaction ids for Visa and
  # Mastercard, so Amex sends the id returned by the CIT. This shows whether that id
  # (provider_transaction_id) is accepted as original_transaction_id.
  def test_mit_with_amex_uses_cit_transaction_id
    auth = @gateway.authorize(@amount, @amex_card, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success auth

    add_cit_network_transaction_id_to_stored_credential(auth)

    purchase = @gateway.purchase(@amount, @amex_card, @options.merge(stored_credential: @stored_credential_mit_options))
    assert_success purchase, "Amex MIT failed with original_transaction_id=#{@stored_credential_mit_options[:network_transaction_id].inspect}: #{purchase.message} (#{purchase.error_code})"
  end

  def test_successful_network_transaction_id_override_with_mastercard
    mastercard = credit_card('2223 0000 1018 1375', { brand: 'master' })

    auth = @gateway.authorize(@amount, mastercard, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success auth

    add_cit_network_transaction_id_to_stored_credential(auth)

    purchase = @gateway.purchase(@amount, mastercard, @options.merge(stored_credential: @stored_credential_mit_options))
    assert_success purchase
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end

    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:client_api_key], transcript)
  end

  def test_successful_authorize_with_3ds_v1_options
    @options[:three_d_secure] = {
      version: '1',
      cavv: 'VGhpcyBpcyBhIHRlc3QgYmFzZTY=',
      eci: '02',
      xid: 'b2h3aDZrd3BJWXVCWEFMbzJqSGQ='
    }

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_match 'AUTHORIZED', response.message
  end

  def test_successful_authorize_with_3ds_v2_options
    @options[:three_d_secure] = {
      version: '2.2.0',
      cavv: 'MTIzNDU2Nzg5MDA5ODc2NTQzMjE=',
      ds_transaction_id: 'f25084f0-5b16-4c0a-ae5d-b24808a95e4b',
      eci: '02',
      three_ds_server_trans_id: 'df8b9557-e41b-4e17-87e9-2328694a2ea0'
    }

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_match 'AUTHORIZED', response.message
  end

  def test_successful_purchase_with_3ds_v2_options
    @options[:three_d_secure] = {
      version: '2.0',
      cavv: 'MTIzNDU2Nzg5MDA5ODc2NTQzMjE=',
      ds_transaction_id: 'f25084f0-5b16-4c0a-ae5d-b24808a95e4b',
      eci: '02',
      three_ds_server_trans_id: 'df8b9557-e41b-4e17-87e9-2328694a2ea0'
    }

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_match 'AUTHORIZED', response.message
  end

  private

  def add_cit_network_transaction_id_to_stored_credential(auth)
    @stored_credential_mit_options[:network_transaction_id] = auth.params['latest_payment_attempt']['provider_transaction_id']
  end

  # The CIT is an authorize and the MIT a purchase, using the id the CIT returned,
  # which is the flow the certification test runs.
  def assert_successful_debit_cit_then_mit(card)
    cit = @gateway.authorize(@amount, card, @options.merge(stored_credential: @stored_credential_cit_options))
    assert_success cit, "Debit CIT failed: #{cit.message} (#{cit.error_code})"

    add_cit_network_transaction_id_to_stored_credential(cit)

    mit = @gateway.purchase(@amount, card, @options.merge(stored_credential: @stored_credential_mit_options))
    assert_success mit, "Debit MIT failed with original_transaction_id=#{@stored_credential_mit_options[:network_transaction_id].inspect}: #{mit.message} (#{mit.error_code})"
    assert_equal 'AUTHORIZED', mit.message
  end
end
