require 'net/http'
require 'net/https'
require File.dirname(__FILE__) + '/GatewayRequest'
require File.dirname(__FILE__) + '/GatewayResponse'

module RocketGate
  class GatewayService
    ROCKETGATE_SERVLET = '/gateway/servlet/ServiceDispatcherAccess'
    ROCKETGATE_CONNECT_TIMEOUT = 10
    ROCKETGATE_READ_TIMEOUT = 90
    ROCKETGATE_PROTOCOL = 'https'
    ROCKETGATE_PORTNO = '443'
    ROCKETGATE_USER_AGENT = 'RG Client - Ruby 1.2'

    LIVE_HOST = 'gw.rocketgate.com'
    LIVE_HOST_16 = 'gw-16.rocketgate.com'
    LIVE_HOST_17 = 'gw-17.rocketgate.com'
    TEST_HOST = 'dev-gw.rocketgate.com'

    def initialize
      @testMode = false
      @rocketGateDNS = LIVE_HOST
      @rocketGateHost = [LIVE_HOST_16, LIVE_HOST_17]
      @rocketGateServlet = ROCKETGATE_SERVLET
      @rocketGateProtocol = ROCKETGATE_PROTOCOL
      @rocketGatePortNo = ROCKETGATE_PORTNO
      @rocketGateConnectTimeout = ROCKETGATE_CONNECT_TIMEOUT
      @rocketGateReadTimeout = ROCKETGATE_READ_TIMEOUT
      super
    end

    def SetTestMode(yesNo)
      if yesNo
        @testMode = true
        @rocketGateHost = [TEST_HOST]
        @rocketGateDNS = TEST_HOST
      else
        @testMode = false
        @rocketGateHost = [LIVE_HOST_16, LIVE_HOST_17]
        @rocketGateDNS = LIVE_HOST
      end
    end

    def SetHost(hostName)
      @rocketGateHost = [hostName]
      @rocketGateDNS = hostName
    end

    def SetProtocol(protocol)
      @rocketGateProtocol = protocol
    end

    def SetPortNo(portNo)
      @rocketGatePortNo = portNo
    end

    def SetServlet(servlet)
      @rocketGateServlet = servlet
    end

    def SetConnectTimeout(timeout)
      if timeout.to_i > 0
        @rocketGateConnectTimeout = timeout.to_i
      end
    end

    def SetReadTimeout(timeout)
      if timeout.to_i > 0
        @rocketGateReadTimeout = timeout.to_i
      end
    end

    def SendTransaction(serverName, request, response)
      urlServlet = request.Get('gatewayServlet')
      urlProtocol = request.Get('gatewayProtocol')
      urlPortNo = request.Get('portNo')

      urlServlet = @rocketGateServlet if urlServlet.nil?
      urlProtocol = @rocketGateProtocol if urlProtocol.nil?
      urlPortNo = @rocketGatePortNo if urlPortNo.nil?

      connectTimeout = request.Get('gatewayConnectTimeout')
      if connectTimeout.nil? || connectTimeout.to_i <= 0
        connectTimeout = @rocketGateConnectTimeout
      end

      readTimeout = request.Get('gatewayReadTimeout')
      if readTimeout.nil? || readTimeout.to_i <= 0
        readTimeout = @rocketGateReadTimeout
      end

      begin
        response.Reset
        requestXML = request.ToXML
        headers = { 'Content-Type' => 'text/xml', 'User-Agent' => ROCKETGATE_USER_AGENT }

        http = Net::HTTP.new(serverName, urlPortNo)
        http.open_timeout = connectTimeout
        http.read_timeout = readTimeout

        urlProtocol = urlProtocol.upcase
        if urlProtocol == 'HTTPS'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end

        results = http.request_post(urlServlet, requestXML, headers)
        body = results.body

      rescue Errno::ECONNREFUSED => ex
        response.Set(GatewayResponse::EXCEPTION, ex.message)
        response.Set(GatewayResponse::RESPONSE_CODE, '3')
        response.Set(GatewayResponse::REASON_CODE, '301')
        return '3'

      rescue Timeout::Error => ex
        response.Set(GatewayResponse::EXCEPTION, ex.message)
        response.Set(GatewayResponse::RESPONSE_CODE, '3')
        response.Set(GatewayResponse::REASON_CODE, '303')
        return '3'

      rescue => ex
        response.Set(GatewayResponse::EXCEPTION, ex.message)
        response.Set(GatewayResponse::RESPONSE_CODE, '3')
        response.Set(GatewayResponse::REASON_CODE, '304')
        return '3'
      end

      response.SetFromXML(body)
      responseCode = response.Get(GatewayResponse::RESPONSE_CODE)
      if responseCode.nil?
        responseCode = '3'
        response.Set(GatewayResponse::EXCEPTION, body)
        response.Set(GatewayResponse::RESPONSE_CODE, '3')
        response.Set(GatewayResponse::REASON_CODE, '400')
      end
      responseCode
    end

    def PerformTransaction(request, response)
      serverName = request.Get('gatewayServer')
      if serverName != nil
        serverName = [serverName]
      else
        serverName = @rocketGateHost
      end

      request.Clear(GatewayRequest::FAILED_SERVER)
      request.Clear(GatewayRequest::FAILED_RESPONSE_CODE)
      request.Clear(GatewayRequest::FAILED_REASON_CODE)
      request.Clear(GatewayRequest::FAILED_GUID)

      if serverName.length > 1
        index = rand(serverName.length)
        if index > 0
          swapper = serverName[0]
          serverName[0] = serverName[index]
          serverName[index] = swapper
        end
      end

      index = 0
      while index < serverName.length do
        results = self.SendTransaction(serverName[index], request, response)

        return true if results == '0'
        return false if results != '3'

        request.Set(GatewayRequest::FAILED_SERVER, serverName[index])
        request.Set(GatewayRequest::FAILED_RESPONSE_CODE,
                    response.Get(GatewayResponse::RESPONSE_CODE))
        request.Set(GatewayRequest::FAILED_REASON_CODE,
                    response.Get(GatewayResponse::REASON_CODE))
        request.Set(GatewayRequest::FAILED_GUID,
                    response.Get(GatewayResponse::TRANSACT_ID))
        index = index + 1
      end
    end

    def PerformTargetedTransaction(request, response)
      request.Clear(GatewayRequest::FAILED_SERVER)
      request.Clear(GatewayRequest::FAILED_RESPONSE_CODE)
      request.Clear(GatewayRequest::FAILED_REASON_CODE)
      request.Clear(GatewayRequest::FAILED_GUID)

      referenceGUID = request.Get(GatewayRequest::REFERENCE_GUID)
      if referenceGUID.nil?
        response.Set(GatewayResponse::RESPONSE_CODE, '4')
        response.Set(GatewayResponse::REASON_CODE, '410')
        return false
      end

      siteString = '0x'
      if referenceGUID.length > 15
        siteString.concat(referenceGUID[0, 2])
      else
        siteString.concat(referenceGUID[0, 1])
      end

      begin
        siteNo = Integer(siteString)
      rescue
        response.Set(GatewayResponse::RESPONSE_CODE, '4')
        response.Set(GatewayResponse::REASON_CODE, '410')
        return false
      end

      serverName = request.Get('gatewayServer')
      if serverName.nil?
        serverName = @rocketGateDNS
        separator = serverName.index('.')
        if separator != nil && separator > 0
          prefix = serverName[0, separator]
          prefix.concat('-')
          prefix.concat(siteNo.to_s)
          prefix.concat(serverName[separator, serverName.length])
          serverName = prefix
        end
      end

      results = self.SendTransaction(serverName, request, response)
      return true if results == '0'

      false
    end

    def PerformConfirmation(request, response)
      confirmGUID = response.Get(GatewayResponse::TRANSACT_ID)
      if confirmGUID.nil?
        response.Set(GatewayResponse::EXCEPTION,
                     'BUG-CHECK - Missing confirmation GUID')
        response.Set(GatewayResponse::RESPONSE_CODE, '3')
        response.Set(GatewayResponse::REASON_CODE, '307')
        return false
      end

      confirmResponse = GatewayResponse.new
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CC_CONFIRM')
      request.Set(GatewayRequest::REFERENCE_GUID, confirmGUID)
      results = self.PerformTargetedTransaction(request, confirmResponse)
      if results
        return true
      end

      response.Set(GatewayResponse::RESPONSE_CODE,
                   confirmResponse.Get(GatewayResponse::RESPONSE_CODE))
      response.Set(GatewayResponse::REASON_CODE,
                   confirmResponse.Get(GatewayResponse::REASON_CODE))
      false
    end

    def PerformAuthOnly(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CC_AUTH')
      results = self.PerformTransaction(request, response)
      if results
        results = self.PerformConfirmation(request, response)
      end
      results
    end

    def PerformTicket(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CC_TICKET')
      self.PerformTargetedTransaction(request, response)
    end

    def PerformPurchase(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CC_PURCHASE')
      results = self.PerformTransaction(request, response)
      if results
        results = self.PerformConfirmation(request, response)
      end
      results
    end

    def PerformCredit(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CC_CREDIT')

      referenceGUID = request.Get(GatewayRequest::REFERENCE_GUID)
      if referenceGUID != nil
        self.PerformTargetedTransaction(request, response)
      else
        self.PerformTransaction(request, response)
      end
    end

    def PerformVoid(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CC_VOID')
      self.PerformTargetedTransaction(request, response)
    end

    def PerformCardScrub(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'CARDSCRUB')
      self.PerformTransaction(request, response)
    end

    def PerformRebillCancel(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'REBILL_CANCEL')
      self.PerformTransaction(request, response)
    end

    def PerformRebillUpdate(request, response)
      request.Set(GatewayRequest::TRANSACTION_TYPE, 'REBILL_UPDATE')

      amount = request.Get(GatewayRequest::AMOUNT)
      if amount.nil? || amount.to_f <= 0.0
        return self.PerformTransaction(request, response)
      end

      results = self.PerformTransaction(request, response)
      if results
        results = self.PerformConfirmation(request, response)
      end
      results
    end
  end
end
