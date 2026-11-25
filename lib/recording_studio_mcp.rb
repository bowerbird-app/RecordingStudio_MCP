# frozen_string_literal: true

require "recording_studio"
require "recording_studio_api"
require "recording_studio_oauth"
require "recording_studio_logs"
require "recording_studio_mcp/version"
require "recording_studio_mcp/skills"
require "recording_studio_mcp/events"
require "recording_studio_mcp/canonical_json"
require "recording_studio_mcp/json_object_schema"
require "recording_studio_mcp/webhook_secret"
require "recording_studio_mcp/webhook_signature"
require "recording_studio_mcp/callback_url"
require "recording_studio_mcp/callback_http"
require "recording_studio_mcp/callback_verifier"
require "recording_studio_mcp/subscription_identity"
require "recording_studio_mcp/event_rpc"
require "recording_studio_mcp/webhook_dispatch"
require "recording_studio_mcp/webhook_delivery"
require "recording_studio_mcp/result_shape"
require "recording_studio_mcp/resources"
require "recording_studio_mcp/recording_card"
require "recording_studio_mcp/outbound_queue"
require "recording_studio_mcp/connection"
require "recording_studio_mcp/connections"
require "recording_studio_mcp/after_commit"
require "recording_studio_mcp/postgres_bus"
require "recording_studio_mcp/fanout"
require "recording_studio_mcp/grant_prime_snapshot"
require "recording_studio_mcp/dispatch_access"
RecordingStudioMcp::GrantPrimeSnapshot.install!
require "recording_studio_mcp/notifier"
require "recording_studio_mcp/change_observer"
require "recording_studio_mcp/listen_stream"
require "recording_studio_mcp/documentation_configuration"
require "recording_studio_mcp/registrations"
require "recording_studio_mcp/tool_name"
require "recording_studio_mcp/server_dsl"
require "recording_studio_mcp/generic_tools"
require "recording_studio_mcp/built_server"
require "recording_studio_mcp/schema_from_contract"
require "recording_studio_mcp/registry"
require "recording_studio_mcp/configuration"
require "recording_studio_mcp/named_api"
require "recording_studio_mcp/protected_resource_metadata"
require "recording_studio_mcp/www_authenticate"
require "recording_studio_mcp/authenticator"
require "recording_studio_mcp/authorized_by"
require "recording_studio_mcp/origin_guard"
require "recording_studio_mcp/transport_security"
require "recording_studio_mcp/instructions"
require "recording_studio_mcp/nested_schema"
require "recording_studio_mcp/field_schema"
require "recording_studio_mcp/catalog"
require "recording_studio_mcp/file_params"
require "recording_studio_mcp/endpoint_schema"
require "recording_studio_mcp/tool_docs"
require "recording_studio_mcp/tools"
require "recording_studio_mcp/metric_tools"
require "recording_studio_mcp/catalogs"
require "recording_studio_mcp/tool_surface"
require "recording_studio_mcp/mcp_ui"
require "recording_studio_mcp/ui_resources"
require "recording_studio_mcp/sse_writer"
require "recording_studio_mcp/sse_stream_body"
require "recording_studio_mcp/request_context"
require "recording_studio_mcp/stream_decision"
require "recording_studio_mcp/streamed_call"
require "recording_studio_mcp/presented_types"
require "recording_studio_mcp/dispatcher"
require "recording_studio_mcp/protocol"
require "recording_studio_mcp/usage_call"
require "recording_studio_mcp/usage_recorder"
require "recording_studio_mcp/logs_registration"
require "recording_studio_mcp/usage_window"
require "recording_studio_mcp/usage_screen"
require "recording_studio_mcp/failing_subscriptions_screen"
require "recording_studio_mcp/admin"
require "recording_studio_mcp/api/access"
require "recording_studio_mcp/metrics"
require "recording_studio_mcp/mcp_copy"
require "recording_studio_mcp/redoc"
require "recording_studio_mcp/documentation"
require "recording_studio_mcp/engine"
require "recording_studio_mcp/routing"

module RecordingStudioMcp
  class << self
    include Registry

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def tool_name(type, action)
      ToolName.call(type, action)
    end

    # Origin RFC 9728 documents for named-API MCP identities
    # (`/.well-known/oauth-protected-resource{mcp_mount}/apis/{api_key}`).
    # Draw this before Oauth's glob so those paths are not 404.
    # Public MCP metadata stays on Oauth `draw_origin_well_known`.
    def draw_named_api_well_known(mapper)
      mount = ProtectedResourceMetadata.mcp_mount_path.delete_prefix("/")
      mapper.get "/.well-known/oauth-protected-resource/#{mount}/apis/:api_key",
                 to: "recording_studio_mcp/oauth_discoveries#protected_resource"
    end

    def register_event(name, &)
      registration = Events.build_registration(name, &)
      configuration.update_event_catalog { |catalog| catalog.add(registration) }
      registration
    end

    def notify(name, recording:)
      parsed = Events.parse(name)
      raise ArgumentError, "unregistered event: #{name}" if parsed.nil? || !event_registered?(parsed)

      Notifier.notify_named(parsed, recording: recording)
    end

    def event_registered?(name)
      configuration.event_catalog.registered?(name)
    end

    def events_registered?
      !configuration.event_catalog.empty?
    end
  end
end
