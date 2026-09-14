# frozen_string_literal: true

module RecordingStudioMcp
  class Configuration
    DEFAULT_PROTOCOL_VERSION = "2025-06-18"
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18].freeze
    DEFAULT_MCP_MOUNT_PATH = "/recording_studio_mcp"

    attr_accessor :oauth_protected_resource_path, :oauth_engine_mount_path, :mcp_mount_path, :protocol_version,
                  :allowed_origins, :instructions_suffix

    def initialize
      @mcp_mount_path = DEFAULT_MCP_MOUNT_PATH
      @oauth_protected_resource_path = "/.well-known/oauth-protected-resource#{DEFAULT_MCP_MOUNT_PATH}"
      @oauth_engine_mount_path = "/recording_studio_oauth"
      @protocol_version = DEFAULT_PROTOCOL_VERSION
      @allowed_origins = []
      @instructions_suffix = nil
    end

    def to_h
      {
        oauth_protected_resource_path: oauth_protected_resource_path,
        oauth_engine_mount_path: oauth_engine_mount_path,
        mcp_mount_path: mcp_mount_path,
        protocol_version: protocol_version,
        allowed_origins: allowed_origins,
        instructions_suffix: instructions_suffix
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end
  end
end
