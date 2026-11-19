# frozen_string_literal: true

require "recording_studio_mcp/resources_page_size"
require_relative "catalogs"
require_relative "configuration/registries"
require_relative "configuration/defaults"

module RecordingStudioMcp
  class Configuration
    include Registries
    include Defaults

    DEFAULT_PROTOCOL_VERSION = "2025-06-18"
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25 2026-07-28].freeze
    LEGACY_PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25].freeze
    MODERN_PROTOCOL_VERSION = "2026-07-28"
    DEFAULT_MCP_MOUNT_PATH = "/recording_studio_mcp"
    DEFAULT_RESOURCES_PAGE_SIZE = 100
    DOC_FIELDS = {
      documentation_enabled: :enabled,
      documentation_access: :access,
      documentation_layout_name: :layout_name
    }.freeze

    attr_accessor :oauth_protected_resource_path, :oauth_engine_mount_path, :mcp_mount_path, :protocol_version,
                  :allowed_origins, :instructions_suffix, :describe_payload, :skill_policy, :events_enabled,
                  :event_subscription_ttl, :event_subscriptions_per_principal, :event_callback_host_allowed
    attr_reader :catalog_metric_resources, :list_parent_id_types, :skill_catalog, :event_catalog,
                :tools, :types, :mcp_skills, :servers

    DOC_FIELDS.each do |public_name, field|
      define_method(public_name) { documentation.public_send(field) }
      define_method(:"#{public_name}=") { |value| documentation.public_send(:"#{field}=", value) }
    end

    def initialize
      reset_paths
      reset_registries
      reset_runtime
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

    def resources_page_size
      @resources_page_size || DEFAULT_RESOURCES_PAGE_SIZE
    end

    def resources_page_size=(value)
      @resources_page_size = ResourcesPageSize.parse(value)
    end

    def to_h
      core_settings.merge(documentation.to_h)
    end

    def validate!
      documentation.validate!
      catalogs.build!
      nil
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
