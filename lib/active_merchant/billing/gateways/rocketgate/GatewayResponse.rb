require 'rexml/document'

module RocketGate
  class GatewayResponse
    VERSION_INDICATOR = 'version'
    AUTH_NO = 'authNo'
    AVS_RESPONSE = 'avsResponse'
    BALANCE_AMOUNT = 'balanceAmount'
    BALANCE_CURRENCY = 'balanceCurrency'
    CARD_TYPE = 'cardType'
    CARD_HASH = 'cardHash'
    CARD_LAST_FOUR = 'cardLastFour'
    CARD_EXPIRATION = 'cardExpiration'
    CARD_COUNTRY = 'cardCountry'
    CARD_REGION = 'cardRegion'
    CARD_DEBIT_CREDIT = 'cardDebitCredit'
    CARD_DESCRIPTION = 'cardDescription'
    CARD_ISSUER_NAME = 'cardIssuerName'
    CARD_ISSUER_PHONE = 'cardIssuerPhone'
    CARD_ISSUER_URL = 'cardIssuerURL'
    CAVV_RESPONSE = 'cavvResponse'
    CVV2_CODE = 'cvv2Code'
    EXCEPTION = 'exception'
    MERCHANT_ACCOUNT = 'merchantAccount'
    PAY_TYPE = 'payType'
    PAY_HASH = 'cardHash'
    PAY_LAST_FOUR = 'cardLastFour'
    REASON_CODE = 'reasonCode'
    REBILL_AMOUNT = 'rebillAmount'
    REBILL_DATE = 'rebillDate'
    REBILL_END_DATE = 'rebillEndDate'
    RESPONSE_CODE = 'responseCode'
    TRANSACT_ID = 'guidNo'
    SCRUB_RESULTS = 'scrubResults'
    SETTLED_AMOUNT = 'approvedAmount'
    SETTLED_CURRENCY = 'approvedCurrency'

    def initialize
      @parameterList = {}
      super
    end

    def Set(key, value)
      @parameterList.delete key
      @parameterList[key] = value
    end

    def Reset
      @parameterList = {}
    end

    def SetFromXML(xmlDocument)
      begin
        xml = REXML::Document.new(xmlDocument)
        if root = REXML::XPath.first(xml, '/gatewayResponse')
          root.elements.to_a.each do |node|
            if node.text != nil
              Set(node.name, node.text.strip)
            end
          end
        else
          Set(EXCEPTION, xmlDocument)
          Set(RESPONSE_CODE, '3')
          Set(REASON_CODE, '400')
        end
      rescue => ex
        Set(EXCEPTION, ex.message)
        Set(RESPONSE_CODE, '3')
        Set(REASON_CODE, '307')
      end
    end

    def Get(key)
      @parameterList[key]
    end
  end
end
