# frozen_string_literal: true

require "recording_studio"
require "recording_studio_api"
require "recording_studio_oauth"
require "recording_studio_mcp/version"
require "recording_studio_mcp/configuration"
require "recording_studio_mcp/www_authenticate"
require "recording_studio_mcp/authenticator"
require "recording_studio_mcp/origin_guard"
require "recording_studio_mcp/transport_security"
require "recording_studio_mcp/instructions"
require "recording_studio_mcp/field_schema"
require "recording_studio_mcp/catalog"
require "recording_studio_mcp/endpoint_schema"
require "recording_studio_mcp/tools"
require "recording_studio_mcp/tool_surface"
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
