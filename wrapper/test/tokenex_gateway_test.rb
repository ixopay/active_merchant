ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../lib/tokenex_gateway'

# IXOONE-3: lightweight fake gateway used only by wallet tests. Echoes the
# constructed payment object's class/source/cryptogram/eci back via the
# AM Response params so tests can assert what the wrapper actually built.
# Lives in the standard ActiveMerchant::Billing namespace so the wrapper's
# `"ActiveMerchant::Billing::#{name}".constantize` lookup resolves it.
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class WalletCaptureGateway < Gateway
      def authorize(_money, paysource, _options = {})
        Response.new(true, 'OK', _capture_payment_metadata(paysource))
      end

      def purchase(_money, paysource, _options = {})
        Response.new(true, 'OK', _capture_payment_metadata(paysource))
      end

      private

      def _capture_payment_metadata(paysource)
        {
          payment_class: paysource.class.name,
          source:        (paysource.source.to_s if paysource.respond_to?(:source)),
          cryptogram:    (paysource.payment_cryptogram if paysource.respond_to?(:payment_cryptogram)),
          eci:           (paysource.eci if paysource.respond_to?(:eci))
        }
      end
    end
  end
end

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
      'ref_num' => 'test_ref_123',
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

  def test_debug_tokenexids_does_not_raise_and_logs_transcript
    # Regression test: the debug hook used to call am_gateway.last_request /
    # am_gateway.last_response, methods that don't exist on ActiveMerchant
    # gateways, which raised NoMethodError and discarded a successful response.
    original = TokenExGateway::DEBUG_TOKENEXIDS.dup
    TokenExGateway::DEBUG_TOKENEXIDS.push('1234567890')

    payload = {
      'tokenex_id' => '1234567890',
      'ref_num' => 'test_ref_debug',
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
  ensure
    TokenExGateway::DEBUG_TOKENEXIDS.replace(original)
  end

  # Regression guard: PSv2 sends its reference number as ref_num (see
  # TransactionRequestBody.RefNum -> JsonProperty("ref_num")). The wrapper
  # used to read 'ref', a key PSv2 never sends, so request_info[:reference]
  # always fell back to a locally generated ID with no relationship to PSv2's
  # own reference number -- silently breaking correlation between a wrapper
  # log entry and the PSv2 request/response that produced it.
  def test_reference_read_from_ref_num_matching_psv2_payload_shape
    payload = {
      'tokenex_id' => '1234567890',
      'ref_num' => 'psv2-generated-reference-42',
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'authorize', 'amount' => 100 },
      'credit_card' => {
        'first_name' => 'Test', 'last_name' => 'User', 'number' => '1',
        'month' => '9', 'year' => (Time.now.year + 1).to_s, 'verification_value' => '123'
      }
    }
    TokenExGateway::DEBUG_TOKENEXIDS.push('1234567890')
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    log = File.read(TokenExGateway::LOG_FILE)
    assert_includes log, 'Reference:psv2-generated-reference-42'
  ensure
    TokenExGateway::DEBUG_TOKENEXIDS.delete('1234567890')
  end

  def test_reference_falls_back_to_generated_id_when_neither_key_present
    payload = {
      'tokenex_id' => '1234567890',
      'gateway' => { 'name' => 'BogusGateway' },
      'transaction' => { 'action' => 'authorize', 'amount' => 100 },
      'credit_card' => {
        'first_name' => 'Test', 'last_name' => 'User', 'number' => '1',
        'month' => '9', 'year' => (Time.now.year + 1).to_s, 'verification_value' => '123'
      }
    }
    TokenExGateway::DEBUG_TOKENEXIDS.push('1234567890')
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    log = File.read(TokenExGateway::LOG_FILE)
    assert_match(/Reference:I[0-9a-f]{32}/, log)
  ensure
    TokenExGateway::DEBUG_TOKENEXIDS.delete('1234567890')
  end

  def test_annotate_transcript_labels_sent_and_received_lines
    utils = Class.new { include Utils }.new
    transcript = <<~TRANSCRIPT
      opening connection to api-demo.airwallex.com:443...
      <- "POST /api/v1/pa/payment_intents/create HTTP/1.1\\r\\n\\r\\n"
      -> "HTTP/1.1 201 Created\\r\\n"
    TRANSCRIPT

    annotated = utils.annotate_transcript(transcript, 'ref-abc123')

    assert_includes annotated, 'opening connection to api-demo.airwallex.com:443...'
    assert_includes annotated,
                     'Request sent by IXOPAY: "POST /api/v1/pa/payment_intents/create HTTP/1.1\r\n\r\n"'
    assert_includes annotated, 'Response recieved by IXOPAY: "HTTP/1.1 201 Created\r\n"'
  end

  # Guards the actual bug: log() only stamps Reference: on the FIRST physical
  # line of a multi-line transcript, so every request/response line after
  # that had no reference at all in a multi-transaction log file. Every
  # annotated line must carry it independently.
  def test_annotate_transcript_stamps_reference_on_every_line
    utils = Class.new { include Utils }.new
    transcript = <<~TRANSCRIPT
      <- "POST /mes-api/tridentApi HTTP/1.1\\r\\n\\r\\n"
      -> "HTTP/1.1 200 OK\\r\\n"
      -> "transaction_id=1&error_code=000\\r\\n"
    TRANSCRIPT

    annotated = utils.annotate_transcript(transcript, 'ref-abc123')

    lines = annotated.lines.reject { |l| l.strip.empty? }
    assert_equal 3, lines.size
    lines.each { |line| assert_match(/\AReference:ref-abc123 /, line) }
  end

  def test_annotate_transcript_leaves_unlabeled_lines_without_reference
    utils = Class.new { include Utils }.new
    transcript = "opening connection to api-demo.airwallex.com:443...\n"

    annotated = utils.annotate_transcript(transcript, 'ref-abc123')

    refute_includes annotated, 'Reference:'
  end

  # Builds one already-annotated "-> " transcript line from real bytes, using
  # String#dump to produce the escaped text (rather than hand-typed \r\n
  # literals, which are error-prone to get right across quoting layers).
  def dump_line(bytes)
    "-> #{bytes.dump}\n"
  end

  # Reproduces the real reported case: a chunked, gzip'd HTTP response comes
  # out of Net::HTTP's debug_output as a dozen-plus lines -- one per header,
  # one hex chunk-size line, the chunk body, a trailing CRLF, interleaved with
  # unprefixed "reading N bytes.../read N bytes" trace noise. This must
  # collapse to exactly two "-> " lines: the combined header block, and the
  # combined (de-chunked) body.
  def test_condense_response_blocks_collapses_chunked_response_to_two_lines
    utils = Class.new { include Utils }.new
    gz = StringIO.new.tap { |io| w = Zlib::GzipWriter.new(io); w.write('transaction_id=1&error_code=000'); w.close }.string.b

    lines = [
      dump_line("HTTP/1.1 200 \r\n"),
      dump_line("Date: Wed, 23 Sep 2026 22:10:45 GMT\r\n"),
      dump_line("Content-Type: text/plain\r\n"),
      dump_line("Transfer-Encoding: chunked\r\n"),
      dump_line("Connection: close\r\n"),
      dump_line("Content-Encoding: gzip\r\n"),
      dump_line("\r\n"),
      dump_line("#{gz.bytesize.to_s(16)}\r\n"),
      "reading #{gz.bytesize} bytes...\n",
      dump_line(gz),
      "read #{gz.bytesize} bytes\n",
      "reading 2 bytes...\n",
      dump_line("\r\n"),
      "read 2 bytes\n",
      dump_line("0\r\n"),
      dump_line("\r\n")
    ]
    transcript = lines.join

    condensed = utils.condense_response_blocks(transcript)
    condensed_lines = condensed.lines
    assert_equal 2, condensed_lines.size, "expected exactly 2 lines, got:\n#{condensed}"
    assert_match(/\AHTTP\/1\.1 200/, condensed_lines[0].match(/-> "(.*)"/m)[1])
    assert_includes condensed_lines[0], 'Transfer-Encoding: chunked'
    assert_includes condensed_lines[0], 'Content-Encoding: gzip'
    refute_includes condensed, 'reading '
    refute_includes condensed, 'read '

    inflated = utils.inflate_gzip_lines(condensed)
    final = utils.annotate_transcript(inflated, 'ref-42')
    final_lines = final.lines
    assert_equal 2, final_lines.size
    assert_match(/\AReference:ref-42 Response recieved by IXOPAY: "HTTP\/1\.1 200/, final_lines[0])
    assert_equal(
      "Reference:ref-42 Response recieved by IXOPAY: #{'transaction_id=1&error_code=000'.dump}\n",
      final_lines[1]
    )
  end

  # The gzip stream can legitimately span more than one chunk. Before
  # reassembly, inflate_gzip_lines only ever saw one chunk at a time and could
  # never have inflated either half. condense_response_blocks reassembles the
  # full body first, so this now inflates correctly.
  def test_condense_response_blocks_reassembles_gzip_split_across_chunks
    utils = Class.new { include Utils }.new
    gz = StringIO.new.tap { |io| w = Zlib::GzipWriter.new(io); w.write('a' * 200); w.close }.string.b
    half = gz.bytesize / 2
    chunk_a = gz.byteslice(0, half)
    chunk_b = gz.byteslice(half, gz.bytesize - half)

    lines = [
      dump_line("HTTP/1.1 200 \r\n"),
      dump_line("Transfer-Encoding: chunked\r\n"),
      dump_line("Content-Encoding: gzip\r\n"),
      dump_line("\r\n"),
      dump_line("#{chunk_a.bytesize.to_s(16)}\r\n"),
      dump_line(chunk_a),
      dump_line("\r\n"),
      dump_line("#{chunk_b.bytesize.to_s(16)}\r\n"),
      dump_line(chunk_b),
      dump_line("\r\n"),
      dump_line("0\r\n"),
      dump_line("\r\n")
    ]
    transcript = lines.join

    condensed = utils.condense_response_blocks(transcript)
    inflated = utils.inflate_gzip_lines(condensed)

    assert_includes inflated, 'a' * 200
  end

  def test_condense_response_blocks_handles_non_chunked_response
    utils = Class.new { include Utils }.new
    lines = [
      dump_line("HTTP/1.1 200 \r\n"),
      dump_line("Content-Type: application/json\r\n"),
      dump_line("Content-Length: 13\r\n"),
      dump_line("\r\n"),
      dump_line("{\"ok\":true}\n")
    ]
    transcript = lines.join

    condensed = utils.condense_response_blocks(transcript)
    condensed_lines = condensed.lines
    assert_equal 2, condensed_lines.size
    body_content = utils.send(:response_line_content, condensed_lines[1])
    assert_equal %({"ok":true}) + "\n", body_content
  end

  # Must never be able to turn a completed, successful transaction into a
  # logged error -- if anything about the shape is unrecognised, fall back to
  # the original, uncondensed transcript rather than raising or corrupting it.
  def test_condense_response_blocks_falls_back_safely_on_unexpected_shape
    utils = Class.new { include Utils }.new
    transcript = dump_line("HTTP/1.1 200 \r\n") + "-> \"this is not a header line at all\"\n"

    result = utils.condense_response_blocks(transcript)

    assert_equal transcript, result
  end

  def test_condense_response_blocks_leaves_request_lines_untouched
    utils = Class.new { include Utils }.new
    transcript = "<- #{"POST /mes-api/tridentApi HTTP/1.1\r\nHost: x\r\n\r\n".dump}\n" \
                 "<- #{'profile_id=x'.dump}\n"

    assert_equal transcript, utils.condense_response_blocks(transcript)
  end

  def test_inflate_gzip_lines_decodes_gzipped_body_line
    utils = Class.new { include Utils }.new
    body = { 'result' => 'ok', 'message' => 'approved' }.to_json
    gzipped = StringIO.new.tap do |io|
      gz = Zlib::GzipWriter.new(io)
      gz.write(body)
      gz.close
    end.string

    transcript = "-> \"HTTP/1.1 200 OK\\r\\n\"\n-> #{gzipped.dump}\n"

    inflated = utils.inflate_gzip_lines(transcript)

    assert_includes inflated, 'approved'
    assert_includes inflated, 'HTTP/1.1 200 OK'
    refute_includes inflated, gzipped
  end

  def test_inflate_gzip_lines_leaves_non_gzip_content_untouched
    utils = Class.new { include Utils }.new
    transcript = "-> \"HTTP/1.1 200 OK\\r\\n\"\n-> \"{\\\"ok\\\":true}\"\n"

    assert_equal transcript, utils.inflate_gzip_lines(transcript)
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

  # ---------- IXOONE-3 wallet support tests ------------------------------
  # These use WalletCaptureGateway (defined at the top of this file) which
  # echoes the constructed payment object's class/source/cryptogram/eci into
  # response params so we can assert the wallet branch did what it should.

  def _wallet_payload(action:, source:, with_cvv: true, cryptogram: 'X', eci: '05', transaction_id: nil)
    cc = {
      'first_name' => 'Test', 'last_name' => 'User',
      'number'     => '1', 'month' => '9', 'year' => (Time.now.year + 1).to_s
    }
    cc['verification_value'] = '123' if with_cvv
    cc['source']             = source             unless source.nil?
    cc['payment_cryptogram'] = cryptogram         unless cryptogram.nil?
    cc['eci']                = eci                unless eci.nil?
    cc['transaction_id']     = transaction_id     unless transaction_id.nil?

    {
      'gateway'     => { 'name' => 'WalletCaptureGateway' },
      'transaction' => { 'action' => action, 'amount' => 100 },
      'credit_card' => cc
    }
  end

  def test_wallet_apple_pay_builds_network_tokenization_credit_card
    # AC: source=apple_pay → NetworkTokenizationCreditCard
    payload = _wallet_payload(action: 'authorize', source: 'apple_pay',
                              cryptogram: 'AP_CRYPTO_1', eci: '05', transaction_id: 'AP_TXID_1')
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)

    assert result['success'], "expected success; got: #{result.inspect}"
    assert_equal 'ActiveMerchant::Billing::NetworkTokenizationCreditCard', result['params']['payment_class']
    assert_equal 'apple_pay',   result['params']['source']
    assert_equal 'AP_CRYPTO_1', result['params']['cryptogram']
    assert_equal '05',          result['params']['eci']
  end

  def test_wallet_google_pay_maps_to_android_pay
    # AC: source=google_pay → NetworkTokenizationCreditCard, with the wrapper
    # translating the public product name to the gem's internal :android_pay symbol.
    payload = _wallet_payload(action: 'purchase', source: 'google_pay',
                              cryptogram: 'GP_CRYPTO_1', eci: '07')
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)

    assert result['success']
    assert_equal 'ActiveMerchant::Billing::NetworkTokenizationCreditCard', result['params']['payment_class']
    assert_equal 'android_pay', result['params']['source']  # the wallet_source_map translation worked
  end

  def test_wallet_invalid_source_rejected
    # Plan addition: invalid source rejected loudly rather than silently falling
    # back to :apple_pay (which is what the gem's source getter would do).
    payload = _wallet_payload(action: 'authorize', source: 'paypal',
                              cryptogram: 'X', eci: '05')
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)

    refute result['success'], "expected failure for unknown wallet source; got: #{result.inspect}"
    assert_match(/Unsupported wallet source/, result['additional_details'].to_s)
  end

  def test_no_source_builds_standard_credit_card
    # AC: source absent → standard CreditCard (regression guard for the
    # non-wallet path).
    payload = _wallet_payload(action: 'authorize', source: nil,
                              cryptogram: nil, eci: nil)
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)

    assert result['success']
    assert_equal 'ActiveMerchant::Billing::CreditCard', result['params']['payment_class']
  end

  def test_wallet_purchase_without_verification_value
    # AC: missing verification_value with wallet source → no error.
    # Network-tokenized payments authenticate via cryptogram + ECI, not CVV.
    payload = _wallet_payload(action: 'purchase', source: 'apple_pay',
                              with_cvv: false,
                              cryptogram: 'AP_CRYPTO_NO_CVV', eci: '05')
    post '/process', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }
    assert last_response.ok?
    result = JSON.parse(last_response.body)

    assert result['success'], "expected success without CVV; got: #{result.inspect}"
    assert_equal 'ActiveMerchant::Billing::NetworkTokenizationCreditCard', result['params']['payment_class']
    assert_equal 'apple_pay', result['params']['source']
  end
end
