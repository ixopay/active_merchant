# Gateway Compatibility Shims
#
# Maps old TokenEx fork option keys and response formats to upstream equivalents.
# This ensures zero breaking changes for existing customers when traffic is routed
# from the legacy ActiveMerchant fork to the IXOPAY upstream fork.
#
# The shims are organized into three phases:
#   1. credential_shim  - Maps old gateway credential keys to new ones (before gateway init)
#   2. options_shim     - Maps old transaction option keys to new ones (before gateway call)
#   3. response_shim    - Normalizes response fields to match legacy format (after gateway call)

module GatewayCompatibility
  # Phase 1: Credential key mapping (applied to gateway login_options before instantiation)
  CREDENTIAL_SHIMS = {
    'ElementGateway' => lambda { |opts|
      opts[:account_id] ||= opts.delete(:acctid) if opts[:acctid]
      opts[:account_token] ||= opts.delete(:password) if opts[:password] && !opts[:account_token]
      opts[:acceptor_id] ||= opts.delete(:merchant_id) if opts[:merchant_id] && !opts[:acceptor_id]
      # Old fork had TokenEx defaults for these; provide sensible defaults if missing
      opts[:application_id] ||= '7714'
      opts[:application_name] ||= 'IXOPAY'
      opts[:application_version] ||= '1.0'
    },
    'LitleGateway' => lambda { |opts|
      # Old fork accepted :user as alias for :login
      opts[:login] ||= opts.delete(:user) if opts[:user]
    }
  }.freeze

  # Phase 2: Transaction option key mapping (applied to additional_options before gateway call)
  OPTIONS_SHIMS = {
    'BluePayGateway' => lambda { |opts|
      opts[:invoice] ||= opts.delete(:invoice_number) if opts[:invoice_number]
      opts[:duplicate_override] ||= opts.delete(:user_data_1) if opts[:user_data_1]
      opts[:doc_type] ||= opts.delete(:option_flags) if opts[:option_flags]
    },
    'PaymentExpressGateway' => lambda { |opts|
      opts[:client_type] ||= opts.delete(:moto_ecommerce_ind) if opts[:moto_ecommerce_ind]
      opts[:txn_data1] ||= opts.delete(:user_data_1) if opts[:user_data_1]
      opts[:txn_data2] ||= opts.delete(:user_data_2) if opts[:user_data_2]
      opts[:txn_data3] ||= opts.delete(:user_data_3) if opts[:user_data_3]
    },
    'MerchantESolutionsGateway' => lambda { |opts|
      opts[:client_reference_number] ||= opts.delete(:customer) if opts[:customer]
    },
    'MaxipagoGateway' => lambda { |opts|
      # Old fork passed :processor per-transaction; upstream expects :processor_id on gateway init.
      # If it shows up in transaction options, move it to a place the gateway can find.
      opts[:processor_id] ||= opts.delete(:processor) if opts[:processor]
    }
  }.freeze

  # Phase 3: Response normalization (applied to response params after gateway call)
  RESPONSE_SHIMS = {
    'NmiGateway' => lambda { |response|
      params = response.params
      # Old fork mapped Auth.net emulator fields for backward compatibility
      params['response_code'] ||= params['response']
      params['transaction_id'] ||= params['transactionid']
      params['authorization_code'] ||= params['authcode']
      params['response_code_nmi'] ||= params['response']

      # Old fork returned "This transaction has been approved" for success
      if response.success? && response.message == 'Succeeded'
        # Patch message to match legacy format
        response.instance_variable_set(:@message, 'This transaction has been approved')
      end
    },
    'MerchantESolutionsGateway' => lambda { |response|
      # Old fork always returned "This transaction has been approved" for code 000
      # New fork already does this, but message for code 085 changed
      # No action needed - upstream behavior is acceptable
    }
  }.freeze

  # Gateway-specific action overrides
  ACTION_OVERRIDES = {
    # PaymentExpress removed void - route to refund instead
    'PaymentExpressGateway' => {
      'void' => lambda { |gateway, auth_ident, additional_options|
        # PaymentExpress void was removed in upstream; use refund with 0 amount
        additional_options[:description] ||= 'Void via refund'
        gateway.refund(0, auth_ident, additional_options)
      }
    }
  }.freeze

  # PaymentExpress refund requires :description - auto-add if missing
  REFUND_DEFAULTS = {
    'PaymentExpressGateway' => lambda { |opts|
      opts[:description] ||= 'Refund'
    }
  }.freeze

  module_function

  def apply_credential_shim(gateway_name, login_options)
    shim = CREDENTIAL_SHIMS[gateway_name]
    shim&.call(login_options)
  end

  def apply_options_shim(gateway_name, additional_options)
    shim = OPTIONS_SHIMS[gateway_name]
    shim&.call(additional_options)
  end

  def apply_response_shim(gateway_name, response)
    shim = RESPONSE_SHIMS[gateway_name]
    shim&.call(response)
  end

  def action_override(gateway_name, action)
    overrides = ACTION_OVERRIDES[gateway_name]
    overrides&.dig(action)
  end

  def apply_refund_defaults(gateway_name, additional_options)
    shim = REFUND_DEFAULTS[gateway_name]
    shim&.call(additional_options)
  end
end
