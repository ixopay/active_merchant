require 'active_merchant/billing/gateways/ideal/ideal_base'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class IdealRabobankGateway < IdealBaseGateway
      class_attribute :test_url, :live_url

      self.test_url = 'https://idealtest.rabobank.nl/ideal/iDeal'
      self.live_url = 'https://ideal.rabobank.nl/ideal/iDeal'
      self.server_pem = File.read(File.dirname(__FILE__) + '/ideal/ideal_rabobank.pem')
    end
  end
end
