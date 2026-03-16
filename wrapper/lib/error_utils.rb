module TokenExGateway
  module ErrorUtils
    ERROR_CODES = {
      invalid_json: { num: 5003, msg: 'Invalid JSON' },
      missing_param: { num: 5004, msg: 'Invalid or missing parameter' },
      unsupported: { num: 5005, msg: 'Unsupported option or value' },
      gw_error: { num: 5050, msg: 'Gateway error' },
      gw_connect_error: { num: 5052, msg: 'Payment Gateway connection error' },
      gw_blocked_error: { num: 5053, msg: 'Payment Gateway is down' },
      unknown: { num: 9999, msg: 'Application error - Contact support' }
    }.freeze

    def build_error(code, additional_details = '')
      error_info = ERROR_CODES.key?(code) ? ERROR_CODES[code] : ERROR_CODES[:unknown]
      {
        'error_number' => error_info[:num],
        'error_message' => error_info[:msg],
        'additional_details' => additional_details
      }.to_json
    end
  end
end
