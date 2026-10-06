# frozen_string_literal: true

module RecordingStudioMcp
  class Configuration
    DEFAULT_PROTOCOL_VERSION = "2025-06-18"
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25 2026-07-28].freeze
    LEGACY_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25].freeze
    MODERN_PROTOCOL_VERSION = "2026-07-28"
    DEFAULT_MCP_MOUNT_PATH = "/recording_studio_mcp"

    attr_accessor :oauth_protected_resource_path, :oauth_engine_mount_path, :mcp_mount_path, :protocol_version,
                  :allowed_origins, :instructions_suffix, :skill_policy, :events_enabled,
                  :event_subscription_ttl, :event_subscriptions_per_principal, :event_callback_host_allowed
    attr_reader :skill_catalog, :event_catalog

    def initialize
      @mcp_mount_path = DEFAULT_MCP_MOUNT_PATH
      @oauth_protected_resource_path = "/.well-known/oauth-protected-resource#{DEFAULT_MCP_MOUNT_PATH}"
      @oauth_engine_mount_path = "/recording_studio_oauth"
      @protocol_version = DEFAULT_PROTOCOL_VERSION
      @allowed_origins = []
      @instructions_suffix = nil
      @skill_catalog = Skills::SkillCatalog.empty
      @event_catalog = Events::Catalog.empty
      @skill_policy = nil
      @events_enabled = false
      @event_subscription_ttl = 24.hours
      @event_subscriptions_per_principal = 50
      @event_callback_host_allowed = nil
    end

    def to_h
      {
        oauth_protected_resource_path: oauth_protected_resource_path,
        oauth_engine_mount_path: oauth_engine_mount_path,
        mcp_mount_path: mcp_mount_path,
        protocol_version: protocol_version,
        allowed_origins: allowed_origins,
        instructions_suffix: instructions_suffix,
        skill_policy: skill_policy,
        events_enabled: events_enabled,
        event_subscription_ttl: event_subscription_ttl,
        event_subscriptions_per_principal: event_subscriptions_per_principal,
        event_callback_host_allowed: event_callback_host_allowed
      }
    end

    def update_skill_catalog
      @skill_catalog = yield(@skill_catalog)
    end

    def update_event_catalog
      @event_catalog = yield(@event_catalog)
    end

    def self.legacy_protocol?(version)
      LEGACY_PROTOCOL_VERSIONS.include?(version.to_s)
    end

    def self.modern_protocol?(version)
      version.to_s == MODERN_PROTOCOL_VERSION
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
