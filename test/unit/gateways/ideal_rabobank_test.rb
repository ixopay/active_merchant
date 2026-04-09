require 'test_helper'

class IdealRabobankTest < Test::Unit::TestCase
  include CommStub

  def setup
    # Generate a self-signed cert + key for testing
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=Test')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    @pem = cert.to_pem + key.to_pem

    @gateway = IdealRabobankGateway.new(
      login: '123456789',
      password: 'testpass',
      pem: @pem
    )
  end

  def test_test_url
    assert_equal 'https://idealtest.rabobank.nl/ideal/iDeal', IdealRabobankGateway.test_url
  end

  def test_live_url
    assert_equal 'https://ideal.rabobank.nl/ideal/iDeal', IdealRabobankGateway.live_url
  end

  def test_server_pem_loaded
    assert IdealRabobankGateway.server_pem.present?
  end

  def test_default_currency_is_eur
    assert_equal 'EUR', IdealRabobankGateway.default_currency
  end

  def test_supports_scrubbing
    assert @gateway.supports_scrubbing?
  end
end
