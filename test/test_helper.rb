# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "active_support/time"
Time.zone ||= "UTC"
require "recording_studio_mcp"

module IsolatedApiConfiguration
  def with_isolated_api_configuration
    original_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
    original = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
    yield
  ensure
    if original_defined
      RecordingStudioApi.instance_variable_set(:@configuration, original)
    elsif RecordingStudioApi.instance_variable_defined?(:@configuration)
      RecordingStudioApi.remove_instance_variable(:@configuration)
    end
  end

  def register_tree_type(name = "Page", api: :public, operations: %i[index show create update],
                         capability_actions: nil)
    attrs = {
      api: api,
      serializer: ->(*) { { title: "Title" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      operations: operations
    }
    attrs[:capability_actions] = capability_actions if capability_actions
    RecordingStudioApi.register_recordable_type_api(name, **attrs)
  end

  def role_grant(role)
    grant = Struct.new(:api_client, :credential, :access_recording, :root_recording, :role).new(
      nil, nil, nil, nil, role
    )
    grant.define_singleton_method(:accessible_recordings) { |**| [] }
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
end

module IsolatedMcpConfiguration
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
