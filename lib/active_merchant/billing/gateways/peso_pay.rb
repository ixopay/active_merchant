module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PesoPayGateway < PayDollarGateway
      self.test_url = 'https://test.pesopay.com/b2cDemo/eng/directPay/payComp.jsp'
      self.live_url = 'https://www.pesopay.com/b2c2/eng/directPay/payComp.jsp'

      self.homepage_url = 'http://www.pesopay.com/'
      self.display_name = 'PesoPay'
    end
  end
end
