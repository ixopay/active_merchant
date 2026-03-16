require 'minitest/autorun'
require 'active_merchant'
require_relative '../lib/gateway_compatibility'

class GatewayCompatibilityTest < Minitest::Test
  # === Credential Shims ===

  def test_element_credential_mapping
    opts = { acctid: 'ACC1', password: 'PASS1', merchant_id: 'MID1' }
    GatewayCompatibility.apply_credential_shim('ElementGateway', opts)

    assert_equal 'ACC1', opts[:account_id]
    assert_equal 'PASS1', opts[:account_token]
    assert_equal 'MID1', opts[:acceptor_id]
    assert_nil opts[:acctid]
    assert_nil opts[:merchant_id]
  end

  def test_element_provides_defaults_for_application_fields
    opts = { account_id: 'ACC1', account_token: 'TOK1', acceptor_id: 'AID1' }
    GatewayCompatibility.apply_credential_shim('ElementGateway', opts)

    assert_equal '7714', opts[:application_id]
    assert_equal 'IXOPAY', opts[:application_name]
    assert_equal '1.0', opts[:application_version]
  end

  def test_element_does_not_overwrite_new_keys
    opts = { acctid: 'OLD', account_id: 'NEW', password: 'OLDPW', account_token: 'NEWTOK' }
    GatewayCompatibility.apply_credential_shim('ElementGateway', opts)

    assert_equal 'NEW', opts[:account_id]
    assert_equal 'NEWTOK', opts[:account_token]
  end

  def test_litle_user_to_login_mapping
    opts = { user: 'testuser', password: 'pass', merchant_id: 'mid' }
    GatewayCompatibility.apply_credential_shim('LitleGateway', opts)

    assert_equal 'testuser', opts[:login]
    assert_nil opts[:user]
  end

  def test_litle_does_not_overwrite_login
    opts = { user: 'old', login: 'new', password: 'pass', merchant_id: 'mid' }
    GatewayCompatibility.apply_credential_shim('LitleGateway', opts)

    assert_equal 'new', opts[:login]
  end

  def test_unknown_gateway_credential_shim_is_noop
    opts = { login: 'test', password: 'pass' }
    original = opts.dup
    GatewayCompatibility.apply_credential_shim('StripeGateway', opts)

    assert_equal original, opts
  end

  # === Option Shims ===

  def test_bluepay_option_mapping
    opts = { invoice_number: 'INV001', user_data_1: '1', option_flags: 'PPD' }
    GatewayCompatibility.apply_options_shim('BluePayGateway', opts)

    assert_equal 'INV001', opts[:invoice]
    assert_equal '1', opts[:duplicate_override]
    assert_equal 'PPD', opts[:doc_type]
    assert_nil opts[:invoice_number]
    assert_nil opts[:user_data_1]
    assert_nil opts[:option_flags]
  end

  def test_payment_express_option_mapping
    opts = { moto_ecommerce_ind: '7', user_data_1: 'D1', user_data_2: 'D2', user_data_3: 'D3' }
    GatewayCompatibility.apply_options_shim('PaymentExpressGateway', opts)

    assert_equal '7', opts[:client_type]
    assert_equal 'D1', opts[:txn_data1]
    assert_equal 'D2', opts[:txn_data2]
    assert_equal 'D3', opts[:txn_data3]
  end

  def test_merchant_esolutions_option_mapping
    opts = { customer: 'CUST123' }
    GatewayCompatibility.apply_options_shim('MerchantESolutionsGateway', opts)

    assert_equal 'CUST123', opts[:client_reference_number]
    assert_nil opts[:customer]
  end

  def test_maxipago_option_mapping
    opts = { processor: '1' }
    GatewayCompatibility.apply_options_shim('MaxipagoGateway', opts)

    assert_equal '1', opts[:processor_id]
    assert_nil opts[:processor]
  end

  def test_unknown_gateway_options_shim_is_noop
    opts = { order_id: '123', amount: 100 }
    original = opts.dup
    GatewayCompatibility.apply_options_shim('AuthorizeNetGateway', opts)

    assert_equal original, opts
  end

  # === Response Shims ===

  def test_nmi_response_field_normalization
    response = mock_response(true, 'Succeeded', {
      'response' => '1',
      'transactionid' => 'TXN123',
      'authcode' => 'AUTH456'
    })

    GatewayCompatibility.apply_response_shim('NmiGateway', response)

    assert_equal '1', response.params['response_code']
    assert_equal 'TXN123', response.params['transaction_id']
    assert_equal 'AUTH456', response.params['authorization_code']
    assert_equal 'This transaction has been approved', response.message
  end

  def test_nmi_response_does_not_change_failure_message
    response = mock_response(false, 'DECLINE', { 'response' => '2' })

    GatewayCompatibility.apply_response_shim('NmiGateway', response)

    assert_equal 'DECLINE', response.message
  end

  # === Action Overrides ===

  def test_payment_express_void_override_exists
    override = GatewayCompatibility.action_override('PaymentExpressGateway', 'void')
    refute_nil override
  end

  def test_no_override_for_standard_gateway
    override = GatewayCompatibility.action_override('StripeGateway', 'void')
    assert_nil override
  end

  # === Refund Defaults ===

  def test_payment_express_refund_adds_description
    opts = {}
    GatewayCompatibility.apply_refund_defaults('PaymentExpressGateway', opts)

    assert_equal 'Refund', opts[:description]
  end

  def test_payment_express_refund_does_not_overwrite_description
    opts = { description: 'Custom refund' }
    GatewayCompatibility.apply_refund_defaults('PaymentExpressGateway', opts)

    assert_equal 'Custom refund', opts[:description]
  end

  private

  def mock_response(success, message, params)
    ActiveMerchant::Billing::Response.new(success, message, params, test: true)
  end
end
