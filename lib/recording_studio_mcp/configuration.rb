# frozen_string_literal: true

module RecordingStudioMcp
  class Configuration
    DEFAULT_PROTOCOL_VERSION = "2025-06-18"
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25 2026-07-28].freeze
    LEGACY_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25].freeze
    MODERN_PROTOCOL_VERSION = "2026-07-28"
    DEFAULT_MCP_MOUNT_PATH = "/recording_studio_mcp"
    DOC_FIELDS = {
      documentation_enabled: :enabled,
      documentation_access: :access,
      documentation_layout_name: :layout_name
    }.freeze

    attr_accessor :oauth_protected_resource_path, :oauth_engine_mount_path, :mcp_mount_path, :protocol_version,
                  :allowed_origins, :instructions_suffix, :describe_payload, :skill_policy, :events_enabled,
                  :event_subscription_ttl, :event_subscriptions_per_principal, :event_callback_host_allowed
    attr_reader :catalog_metric_resources, :list_parent_id_types, :skill_catalog, :event_catalog

    DOC_FIELDS.each do |public_name, field|
      define_method(public_name) { documentation.public_send(field) }
      define_method(:"#{public_name}=") { |value| documentation.public_send(:"#{field}=", value) }
    end

    def initialize
      @mcp_mount_path = DEFAULT_MCP_MOUNT_PATH
      @oauth_protected_resource_path = "/.well-known/oauth-protected-resource#{DEFAULT_MCP_MOUNT_PATH}"
      @oauth_engine_mount_path = "/recording_studio_oauth"
      @protocol_version = DEFAULT_PROTOCOL_VERSION
      @allowed_origins = []
      @instructions_suffix = nil
      @describe_payload = nil
      @skill_catalog = Skills::SkillCatalog.empty
      @event_catalog = Events::Catalog.empty
      @skill_policy = nil
      @events_enabled = false
      @event_subscription_ttl = 24.hours
      @event_subscriptions_per_principal = 50
      @event_callback_host_allowed = nil
      @catalog_metric_resources = nil
      @list_parent_id_types = nil
    end

    def documentation
      @documentation ||= DocumentationConfiguration.new
    end

    def catalog_metric_resources=(resources)
      @catalog_metric_resources = resources.nil? ? nil : Array(resources).map(&:to_s).uniq.freeze
    end

    def list_parent_id_types=(types)
      @list_parent_id_types = types.nil? ? nil : Array(types).map(&:to_s).uniq.freeze
    end

    def to_h
      core_settings.merge(documentation.to_h)
    end

    def validate!
      documentation.validate!
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

    private

    def core_settings
      {
        oauth_protected_resource_path: oauth_protected_resource_path,
        oauth_engine_mount_path: oauth_engine_mount_path,
        mcp_mount_path: mcp_mount_path,
        protocol_version: protocol_version,
        allowed_origins: allowed_origins,
        instructions_suffix: instructions_suffix,
        describe_payload: describe_payload,
        skill_policy: skill_policy,
        events_enabled: events_enabled,
        event_subscription_ttl: event_subscription_ttl,
        event_subscriptions_per_principal: event_subscriptions_per_principal,
        event_callback_host_allowed: event_callback_host_allowed,
        catalog_metric_resources: catalog_metric_resources,
        list_parent_id_types: list_parent_id_types
      }
    end
  end
end
