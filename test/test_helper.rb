# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require_relative "recordable_metric_tool_helpers"
require_relative "isolated_mcp_servers"
require "minitest/autorun"
require "rails"
require "active_support/time"
Time.zone ||= "UTC"
require "recording_studio_mcp"

module IsolatedApiConfiguration
  include IsolatedMcpServers

  def with_isolated_api_configuration
    with_isolated_mcp_configuration do
      original_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
      original = RecordingStudioApi.instance_variable_get(:@configuration)
      RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
      begin
        yield
      ensure
        if original_defined
          RecordingStudioApi.instance_variable_set(:@configuration, original)
        elsif RecordingStudioApi.instance_variable_defined?(:@configuration)
          RecordingStudioApi.remove_instance_variable(:@configuration)
        end
      end
    end
  end

  def register_tree_type(name = "Page", **options)
    api = options.fetch(:api, :public)
    RecordingStudioApi.register_recordable_type_api(name, **tree_type_attrs(options))
    RecordingStudioMcp.register_type(type: name, description: options[:description].to_s)
    ensure_tree_server(api)
  end

  def role_grant(role)
    grant = Struct.new(:api_client, :credential, :access_recording, :root_recording, :role).new(
      nil, nil, nil, nil, role
    )
    grant.define_singleton_method(:accessible_recordings) { |**| [] }
    grant.define_singleton_method(:authorized?) { |**| true }
    grant
  end

  def register_ping_capability(api: :public, required_role: nil)
    return if RecordingStudioApi.capability_action(:ping, api: api)

    RecordingStudioApi.register_capability_action(
      :ping,
      capability: :accessible,
      api: api,
      required_role: required_role,
      handler: ->(_context) { { json: { ok: true } } }
    )
  end

  private

  def tree_type_attrs(options)
    extras = options.except(:api, :operations, :capability_actions, :openapi, :description)
    attrs = {
      api: options.fetch(:api, :public),
      serializer: ->(*) { { title: "Title" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      operations: options.fetch(:operations, %i[index show create update])
    }.merge(extras)
    attrs[:capability_actions] = options[:capability_actions] if options[:capability_actions]
    attrs[:openapi] = options[:openapi] if options[:openapi]
    attrs
  end
end

module IsolatedMcpConfiguration
  def include_registered_skills!(api: :public)
    names = RecordingStudioMcp.configuration.mcp_skills.keys
    return if names.empty?

    existing = RecordingStudioMcp.configuration.servers[api.to_s]
    tools = Array(existing&.included_tools).map(&:name)
    allow = existing&.allow_sensitive || false
    RecordingStudioMcp.register_server(api, api: api, allow_sensitive: allow) do
      include_tools(*tools)
      include_skills(*names)
    end
  end

  def with_isolated_mcp_configuration
    original = RecordingStudioMcp.instance_variable_get(:@configuration)
    RecordingStudioMcp.instance_variable_set(:@configuration, RecordingStudioMcp::Configuration.new)
    yield
  ensure
    if original
      RecordingStudioMcp.instance_variable_set(:@configuration, original)
    elsif RecordingStudioMcp.instance_variable_defined?(:@configuration)
      RecordingStudioMcp.remove_instance_variable(:@configuration)
    end
  end
end

module ConnectionCleanup
  def teardown
    RecordingStudioMcp::Connections.clear!
    super
  end
end

module Minitest
  class Test
    include IsolatedApiConfiguration
    include IsolatedMcpConfiguration
    prepend ConnectionCleanup
  end
end
