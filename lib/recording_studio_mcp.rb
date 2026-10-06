# frozen_string_literal: true

require "recording_studio"
require "recording_studio_api"
require "recording_studio_oauth"
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
require "recording_studio_mcp/notifier"
require "recording_studio_mcp/change_observer"
require "recording_studio_mcp/listen_stream"
require "recording_studio_mcp/configuration"
require "recording_studio_mcp/protected_resource_metadata"
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
require "recording_studio_mcp/sse_writer"
require "recording_studio_mcp/sse_stream_body"
require "recording_studio_mcp/request_context"
require "recording_studio_mcp/stream_decision"
require "recording_studio_mcp/streamed_call"
require "recording_studio_mcp/dispatcher"
require "recording_studio_mcp/protocol"
require "recording_studio_mcp/usage_call"
require "recording_studio_mcp/usage_recorder"
require "recording_studio_mcp/aggregate_usage"
require "recording_studio_mcp/maintain_usage"
require "recording_studio_mcp/usage_window"
require "recording_studio_mcp/usage_screen"
require "recording_studio_mcp/admin"
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

    def register_skill(name, path:, available_if: nil)
      registration = skill_registration(name, path, available_if)
      configuration.update_skill_catalog { |catalog| catalog.add(registration) }
      registration
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
      catalog = configuration.skill_catalog
      policy = configuration.skill_policy
      catalog.select { |registration| expose_skill?(registration, policy, access_grant) }
    end

    private

    def skill_registration(name, path, available_if)
      parsed_name = Skills::SkillName.parse(name)
      raise ArgumentError, "invalid skill name" if parsed_name.nil?
      raise ArgumentError, "available_if must be callable" unless skill_hook?(available_if)

      Skills::Registration.new(name: parsed_name, path: absolute_skill_path(path), available_if: available_if)
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
