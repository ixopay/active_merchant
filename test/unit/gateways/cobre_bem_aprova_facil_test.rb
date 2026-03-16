require 'test_helper'

class CobreBemAprovaFacilTest < Test::Unit::TestCase
  def setup
    @gateway = CobreBemAprovaFacilGateway.new(
      login: 'testmerchant'
    )
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @options = {
      order_id: 'order123',
      billing_address: address,
      ip: '127.0.0.1'
    }
  end

  def test_successful_authorize
    stub_http_response(successful_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_success response
    assert response.test?
    assert response.authorization.present?
  end

  def test_failed_authorize
    stub_http_response(failed_authorize_response)
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
  end

  def test_successful_capture
    stub_http_response(successful_capture_response)
    response = @gateway.capture(@amount, 'order123;txn456', @options)

    assert_success response
  end

  def test_successful_refund
    stub_http_response(successful_refund_response)
    response = @gateway.refund(@amount, 'order123;txn456', @options)

    assert_success response
  end

  def test_successful_void
    stub_http_response(successful_void_response)
    response = @gateway.void('order123;txn456', @options)

    assert_success response
  end

  def test_capture_requires_authorization
    assert_raise(ArgumentError) do
      @gateway.capture(@amount, nil, @options)
    end
  end

  def test_void_requires_authorization
    assert_raise(ArgumentError) do
      @gateway.void(nil, @options)
    end
  end

  def test_html_error_response
    stub_http_response('<html><body>Error</body></html>')
    response = @gateway.authorize(@amount, @credit_card, @options)

    assert_failure response
    assert_match(/HTML Error/, response.message)
  end

  def test_scrubbing
    assert @gateway.supports_scrubbing?

    transcript = 'NumeroCartao=4111111111111111&CodigoSeguranca=123&other=data'
    scrubbed = @gateway.scrub(transcript)

    assert_no_match(/4111111111111111/, scrubbed)
    assert_no_match(/CodigoSeguranca=123/, scrubbed)
    assert_match(/NumeroCartao=\[FILTERED\]/, scrubbed)
    assert_match(/CodigoSeguranca=\[FILTERED\]/, scrubbed)
  end

  private

  def stub_http_response(body)
    http_response = stub(body: body, code: '200')
    http_session = stub
    http_session.stubs(:request).returns(http_response)
    Net::HTTP.any_instance.stubs(:start).yields(http_session).returns(http_response)
  end

  def successful_authorize_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ResultadoAprovaFacil>
        <TransacaoAprovada>true</TransacaoAprovada>
        <ResultadoSolicitacaoAprovacao>Aprovada</ResultadoSolicitacaoAprovacao>
        <Transacao>txn789</Transacao>
        <ResultadoAVS>Y</ResultadoAVS>
      </ResultadoAprovaFacil>
    XML
  end

  def failed_authorize_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ResultadoAprovaFacil>
        <TransacaoAprovada>false</TransacaoAprovada>
        <ResultadoSolicitacaoAprovacao>Recusada</ResultadoSolicitacaoAprovacao>
      </ResultadoAprovaFacil>
    XML
  end

  def successful_capture_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ResultadoAprovaFacil>
        <ResultadoSolicitacaoConfirmacao>Confirmada</ResultadoSolicitacaoConfirmacao>
      </ResultadoAprovaFacil>
    XML
  end

  def successful_refund_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ResultadoAprovaFacil>
        <ResultadoSolicitacaoCancelamento>Cancelada</ResultadoSolicitacaoCancelamento>
      </ResultadoAprovaFacil>
    XML
  end

  def successful_void_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ResultadoAprovaFacil>
        <ResultadoSolicitacaoCancelamento>Cancelada</ResultadoSolicitacaoCancelamento>
      </ResultadoAprovaFacil>
    XML
  end
end
