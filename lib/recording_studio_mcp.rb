# frozen_string_literal: true

require "recording_studio"
require "recording_studio_api"
require "recording_studio_oauth"
require "recording_studio_mcp/version"
require "recording_studio_mcp/configuration"
require "recording_studio_mcp/www_authenticate"
require "recording_studio_mcp/authenticator"
require "recording_studio_mcp/catalog"
require "recording_studio_mcp/tools"
require "recording_studio_mcp/dispatcher"
require "recording_studio_mcp/protocol"
require "recording_studio_mcp/engine"

module RecordingStudioMcp
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end
  end
end
