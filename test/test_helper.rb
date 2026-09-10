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

  def register_tree_type(name = "Page")
    RecordingStudioApi.register_recordable_type_api(
      name,
      serializer: ->(*) { { title: "Title" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      operations: %i[index show create update]
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

module Minitest
  class Test
    include IsolatedApiConfiguration
    include IsolatedMcpConfiguration
  end
end
