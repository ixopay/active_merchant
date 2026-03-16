module RocketGate
  class GatewayRequest
    VERSION_INDICATOR = 'version'
    VERSION_NUMBER = 'R1.2'

    AFFILIATE = 'affiliate'
    AMOUNT = 'amount'
    AVS_CHECK = 'avsCheck'
    BILLING_ADDRESS = 'billingAddress'
    BILLING_CITY = 'billingCity'
    BILLING_COUNTRY = 'billingCountry'
    BILLING_STATE = 'billingState'
    BILLING_TYPE = 'billingType'
    BILLING_ZIPCODE = 'billingZipCode'
    CARDNO = 'cardNo'
    CARD_HASH = 'cardHash'
    CURRENCY = 'currency'
    CUSTOMER_FIRSTNAME = 'customerFirstName'
    CUSTOMER_LASTNAME = 'customerLastName'
    CVV2 = 'cvv2'
    CVV2_CHECK = 'cvv2Check'
    EMAIL = 'email'
    EXPIRE_MONTH = 'expireMonth'
    EXPIRE_YEAR = 'expireYear'
    IPADDRESS = 'ipAddress'
    MERCHANT_ACCOUNT = 'merchantAccount'
    MERCHANT_CUSTOMER_ID = 'merchantCustomerID'
    MERCHANT_DESCRIPTOR = 'merchantDescriptor'
    MERCHANT_INVOICE_ID = 'merchantInvoiceID'
    MERCHANT_ID = 'merchantID'
    MERCHANT_PASSWORD = 'merchantPassword'
    MERCHANT_SITE_ID = 'merchantSiteID'
    PARTIAL_AUTH_FLAG = 'partialAuthFlag'
    PAY_HASH = 'cardHash'
    REBILL_FREQUENCY = 'rebillFrequency'
    REBILL_AMOUNT = 'rebillAmount'
    REBILL_START = 'rebillStart'
    REBILL_END_DATE = 'rebillEndDate'
    REFERENCE_GUID = 'referenceGUID'
    REFERRING_MERCHANT_ID = 'referringMerchantID'
    REFERRED_CUSTOMER_ID = 'referredCustomerID'
    SCRUB = 'scrub'
    TRANSACT_ID = 'referenceGUID'
    TRANSACTION_TYPE = 'transactionType'
    UDF01 = 'udf01'
    UDF02 = 'udf02'
    USERNAME = 'username'
    FAILED_SERVER = 'failedServer'
    FAILED_GUID = 'failedGUID'
    FAILED_RESPONSE_CODE = 'failedResponseCode'
    FAILED_REASON_CODE = 'failedReasonCode'

    GATEWAY_CONNECT_TIMEOUT = 'gatewayConnectTimeout'
    GATEWAY_READ_TIMEOUT = 'gatewayReadTimeout'

    def initialize
      @parameterList = {}
      self.Set(VERSION_INDICATOR, VERSION_NUMBER)
      super
    end

    def Set(key, value)
      @parameterList.delete key
      if value != nil
        @parameterList[key] = value
      end
    end

    def Clear(key)
      @parameterList.delete key
    end

    def Get(key)
      @parameterList[key]
    end

    def ToXML
      xmlDocument = '<?xml version="1.0" encoding="UTF-8"?>'
      xmlDocument.concat('<gatewayRequest>')

      @parameterList.each_pair do |key, value|
        key = key.to_s
        value = value.to_s

        xmlDocument.concat('<')
        xmlDocument.concat(key)
        xmlDocument.concat('>')

        value = value.gsub('&', '&amp;')
        value = value.gsub('<', '&lt;')
        value = value.gsub('>', '&gt;')
        xmlDocument.concat(value)

        xmlDocument.concat('</')
        xmlDocument.concat(key)
        xmlDocument.concat('>')
      end

      xmlDocument.concat('</gatewayRequest>')
      xmlDocument
    end
  end
end
