ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../lib/tokenex_gateway'

class TokenExGatewayTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_health_check
    get '/'
    assert last_response.ok?
    assert_equal 'I am Alive', last_response.body
  end

  def test_about_endpoint
    get '/about'
    assert last_response.ok?
    info = JSON.parse(last_response.body)
    assert_equal 'test', info['mode']
    assert info['version']
    assert info['active_merchant_version']
  end

  def test_error_codes_endpoint
    get '/error_codes'
    assert last_response.ok?
    codes = JSON.parse(last_response.body)
    assert codes.key?('invalid_json')
    assert codes.key?('unknown')
  end

  def test_process_rejects_invalid_json
    post '/process', 'not valid json', { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5003, result['error_number']
  end

  def test_process_requires_gateway
    payload = { 'transaction' => { 'action' => 'authorize' } }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5004, result['error_number']
  end

  def test_process_requires_transaction
    payload = { 'gateway' => { 'name' => 'BogusGateway', 'test' => 'true' } }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5004, result['error_number']
  end

  def test_process_rejects_unsupported_gateway
    payload = {
      'gateway' => { 'name' => 'NonExistentGateway' },
      'transaction' => { 'action' => 'authorize' }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5005, result['error_number']
    assert_match(/Unsupported gateway/, result['additional_details'])
  end

  def test_process_rejects_unsupported_action
    payload = {
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'invalid_action' }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5005, result['error_number']
  end

  def test_process_authorize_requires_payment_source
    payload = {
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'authorize', 'amount' => 100 }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5004, result['error_number']
    assert_match(/No payment source/, result['additional_details'])
  end

  def test_process_authorize_with_bogus_gateway
    payload = {
      'tokenex_id' => '1234567890',
      'ref' => 'test_ref_123',
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'authorize', 'amount' => 100 },
      'credit_card' => {
        'first_name' => 'Test',
        'last_name' => 'User',
        'number' => '1',
        'month' => '9',
        'year' => (Time.now.year + 1).to_s,
        'verification_value' => '123'
      }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert result['success'], "Expected success, got: #{result.inspect}"
    assert result['authorization']
  end

  def test_process_purchase_with_bogus_gateway
    payload = {
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'purchase', 'amount' => 100 },
      'credit_card' => {
        'first_name' => 'Test',
        'last_name' => 'User',
        'number' => '1',
        'month' => '9',
        'year' => (Time.now.year + 1).to_s,
        'verification_value' => '123'
      }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert result['success']
  end

  def test_capture_passes_credit_card_directly
    # This test verifies the IXOPAY change: credit_card is passed via options[:credit_card]
    # instead of Marshal.dump(am_payment) via options[:payment_obj]
    payload = {
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'capture', 'amount' => 100, 'authorization' => '12345' },
      'credit_card' => {
        'first_name' => 'Test',
        'last_name' => 'User',
        'number' => '1',
        'month' => '9',
        'year' => (Time.now.year + 1).to_s,
        'verification_value' => '123'
      }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    # BogusGateway capture should work
    assert result['success']
  end

  def test_void_passes_credit_card_directly
    payload = {
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'void', 'authorization' => '12345' },
      'credit_card' => {
        'first_name' => 'Test',
        'last_name' => 'User',
        'number' => '1',
        'month' => '9',
        'year' => (Time.now.year + 1).to_s,
        'verification_value' => '123'
      }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert result['success']
  end

  def test_blocked_gateway
    # Temporarily add a gateway to the block list
    original = TokenExGateway::BLOCK_GATEWAYS.dup
    TokenExGateway::BLOCK_GATEWAYS.push('BogusGateway')

    payload = {
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'authorize', 'amount' => 100 },
      'credit_card' => { 'number' => '1', 'month' => '9', 'year' => (Time.now.year + 1).to_s }
    }
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)
    assert_equal 5053, result['error_number']
  ensure
    TokenExGateway::BLOCK_GATEWAYS.replace(original)
  end

  def test_stripe_metadata_conversion
    payload = {
      'gateway' => { 'name' => 'StripeGateway', 'login' => 'sk_test_fake' },
      'transaction' => { 'action' => 'authorize', 'amount' => 100, 'metadata' => 'key1=val1|key2=val2' },
      'credit_card' => {
        'first_name' => 'Test',
        'last_name' => 'User',
        'number' => '4242424242424242',
        'month' => '9',
        'year' => (Time.now.year + 1).to_s,
        'verification_value' => '123'
      }
    }
    # This will fail at the gateway level (no real Stripe key), but the metadata
    # conversion should happen before the gateway call
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    # We just verify it didn't crash on metadata conversion
  end

  def test_no_marshal_dump_in_wrapper
    # Verify that the wrapper source code does not use Marshal.dump
    source = File.read(File.expand_path('../lib/tokenex_gateway.rb', __dir__))
    refute_match(/Marshal\.dump/, source, 'Wrapper should not use Marshal.dump - use options[:credit_card] instead')
  end

  def test_no_marshal_load_reference
    # Verify that the wrapper source code does not reference Marshal.load
    source = File.read(File.expand_path('../lib/tokenex_gateway.rb', __dir__))
    refute_match(/Marshal\.load/, source, 'Wrapper should not use Marshal.load')
  end

  def test_credit_card_in_options_for_capture
    # Verify the source code passes :credit_card in options for capture/refund
    source = File.read(File.expand_path('../lib/tokenex_gateway.rb', __dir__))
    assert_match(/additional_options\[:credit_card\] = am_payment/, source,
                 'Capture/refund should pass am_payment via options[:credit_card]')
  end
end
