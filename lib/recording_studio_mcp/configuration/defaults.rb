# frozen_string_literal: true

module RecordingStudioMcp
  class Configuration
    module Defaults
      private

      def reset_paths
        @mcp_mount_path = DEFAULT_MCP_MOUNT_PATH
        @oauth_protected_resource_path = "/.well-known/oauth-protected-resource#{DEFAULT_MCP_MOUNT_PATH}"
        @oauth_engine_mount_path = "/recording_studio_oauth"
        @protocol_version = DEFAULT_PROTOCOL_VERSION
      end

      def reset_registries
        @skill_catalog = RecordingStudioMcp::Skills::SkillCatalog.empty
        @event_catalog = Events::Catalog.empty
        @tools = {}
        @types = {}
        @mcp_skills = {}
        @servers = {}
        GenericTools.install(self)
      end

      def reset_runtime
        @allowed_origins = []
        @instructions_suffix = nil
        @describe_payload = nil
        @skill_policy = nil
        @events_enabled = false
        @event_subscription_ttl = 24.hours
        @event_subscriptions_per_principal = 50
        @event_callback_host_allowed = nil
        @catalog_metric_resources = nil
        @list_parent_id_types = nil
      end

      def core_settings
        path_settings.merge(runtime_settings)
      end

      def path_settings
        {
          oauth_protected_resource_path: oauth_protected_resource_path,
          oauth_engine_mount_path: oauth_engine_mount_path,
          mcp_mount_path: mcp_mount_path,
          protocol_version: protocol_version
        }
      end

      def runtime_settings
        {
          allowed_origins: allowed_origins, instructions_suffix: instructions_suffix,
          describe_payload: describe_payload, skill_policy: skill_policy,
          events_enabled: events_enabled, event_subscription_ttl: event_subscription_ttl,
          event_subscriptions_per_principal: event_subscriptions_per_principal,
          event_callback_host_allowed: event_callback_host_allowed,
          catalog_metric_resources: catalog_metric_resources, list_parent_id_types: list_parent_id_types,
          resources_page_size: resources_page_size
        }
      end
    end
  end
end
