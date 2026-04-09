module TokenExGateway
  MODE = (ENV['RACK_ENV'] == 'production') ? :production : :test
  LOG_FILE = ENV.fetch('LOG_FILE', File.expand_path('../log/application.log', File.dirname(__FILE__)))

  # TokenEx IDs to enable debug logging. e.g. ['9186070989', '9186633194']
  DEBUG_TOKENEXIDS = ENV.fetch('DEBUG_TOKENEXIDS', '').split(',').map(&:strip)

  # Gateways to block in the event a gateway is down. e.g. ['AuthorizeNetGateway']
  BLOCK_GATEWAYS = ENV.fetch('BLOCK_GATEWAYS', '').split(',').map(&:strip)
end
