require 'active_merchant/billing/gateways/cc5'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class IsbankGateway < CC5Gateway
      self.live_url = 'https://sanalpos.isbank.com.tr/fim/api'
      self.test_url = 'https://entegrasyon.asseco-see.com.tr/fim/api'

      self.supported_countries = ['TR']
      self.supported_cardtypes = %i[visa master]

      self.display_name = 'Isbank'
      self.homepage_url = 'https://www.isbank.com.tr'
    end
  end
end
