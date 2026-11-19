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
require "recording_studio_mcp/server_dsl"
require "recording_studio_mcp/generic_tools"
require "recording_studio_mcp/built_server"
require "recording_studio_mcp/schema_from_contract"
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
require "recording_studio_mcp/redoc"
require "recording_studio_mcp/documentation"
require "recording_studio_mcp/engine"
require "recording_studio_mcp/routing"

module RecordingStudioMcp
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
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

    def register_tool(name:, title:, description:, type: nil, operation: nil, action: nil, endpoint: nil,
                      input: {}, output: nil)
      registration = tool_registration(
        name: name, type: type, operation: operation, action: action, endpoint: endpoint,
        title: title, description: description, input: input, output: output
      )
      configuration.add_tool(registration)
    end

    def register_type(type:, description:)
      configuration.add_type(Registrations::Type.new(type: type.to_s, description: description.to_s))
    end

    def register_skill(legacy_name = nil, name: nil, path: nil, available_if: nil, type: nil, title: nil,
                       description: nil, body: nil, tools: [])
      registration = skill_registration(
        name || legacy_name,
        path: path,
        available_if: available_if,
        type: type,
        title: title,
        description: description,
        body: body,
        tools: tools
      )
      configuration.add_skill(registration)
      configuration.update_skill_catalog { |catalog| catalog.add(skills_entry(registration)) }
      registration
    end

    def register_server(name, api:, allow_sensitive: false, &block)
      dsl = ServerDsl.new
      dsl.instance_eval(&block) if block
      configuration.add_server(
        Registrations::Server.new(
          name: name.to_s,
          api: api,
          allow_sensitive: allow_sensitive,
          included_tools: dsl.included_tools,
          included_skills: dsl.included_skills
        )
      )
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

    def exposed_skills(access_grant:)
      policy = configuration.skill_policy
      skills_for_grant(access_grant).select { |registration| expose_skill?(registration, policy, access_grant) }
    end

    private

    def tool_registration(name:, type:, operation:, action:, endpoint:, title:, description:, input:, output:)
      target = tool_target(operation: operation, action: action, endpoint: endpoint)
      Registrations::Tool.new(
        name: name.to_s,
        type: type&.to_s,
        target: target,
        title: title.to_s,
        description: description.to_s,
        input: stringify_tool_input(input),
        output: output
      )
    end

    def tool_target(operation:, action:, endpoint:)
      kinds = { operation: operation, action: action, endpoint: endpoint }.compact
      raise ArgumentError, "register_tool requires exactly one of operation, action, or endpoint" unless kinds.one?

      kind, value = kinds.first
      Registrations::ToolTarget.new(kind: kind, value: value.to_sym)
    end

    def stringify_tool_input(input)
      return {} if input.blank?
      raise ArgumentError, "input must be an object" unless input.respond_to?(:to_h)

      input.to_h.to_h do |field, meta|
        raise ArgumentError, "input #{field} must be an object" unless meta.respond_to?(:to_h)

        [field.to_s, meta.to_h.transform_keys(&:to_sym)]
      end
    end

    def skills_for_grant(access_grant)
      server = configuration.catalogs.server_for(api: Catalog.api_from(access_grant))
      return configuration.skill_catalog.to_a if server.nil?

      server.skills.values.map { |skill| skills_entry(skill) }
    end

    def skill_registration(name, path:, available_if:, type:, title:, description:, body:, tools:)
      parsed_name = Skills::SkillName.parse(name)
      raise ArgumentError, "invalid skill name" if parsed_name.nil?
      raise ArgumentError, "available_if must be callable" unless skill_hook?(available_if)

      Registrations::Skill.new(
        name: parsed_name,
        type: type&.to_s,
        title: title.to_s.presence,
        description: description.to_s.presence,
        body: body,
        tools: Array(tools).map(&:to_s),
        path: path.present? ? absolute_skill_path(path) : nil,
        available_if: available_if
      )
    end

    def skills_entry(registration)
      Skills::Registration.new(
        name: registration.name,
        path: registration.path,
        available_if: registration.available_if,
        type: registration.type,
        title: registration.title,
        description: registration.description,
        body: registration.body,
        tools: registration.tools
      )
    end

    def skill_hook?(available_if)
      available_if.nil? || available_if.respond_to?(:call)
    end

    def absolute_skill_path(path)
      Pathname.new(File.expand_path(path.to_s))
    end

    def expose_skill?(registration, policy, access_grant)
      skill_available?(registration, access_grant) && skill_allowed?(policy, registration, access_grant)
    end

    def skill_available?(registration, access_grant)
      hook = registration.available_if
      hook.nil? || hook.call(access_grant: access_grant) == true
    end

    def skill_allowed?(policy, registration, access_grant)
      return true if policy.nil?
      return false unless policy.respond_to?(:call)

      policy.call(skill: registration, access_grant: access_grant) == true
    end
  end
end
