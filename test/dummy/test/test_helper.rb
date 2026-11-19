# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/oauth_dummy_helpers"
require_relative "support/output_schema_check"

module ConnectionCleanup
  def teardown
    RecordingStudioMcp::Connections.clear!
    super
  end
end

module DummyMcpIsolation
  def capture_mcp_registry
    config = RecordingStudioMcp.configuration
    @captured_mcp_tools = config.tools.dup
    @captured_mcp_types = config.types.dup
    @captured_mcp_skills = config.mcp_skills.dup
    @captured_mcp_servers = config.servers.dup
  end

  def restore_mcp_registry
    return unless @captured_mcp_servers

    config = RecordingStudioMcp.configuration
    config.instance_variable_set(:@tools, @captured_mcp_tools.dup)
    config.instance_variable_set(:@types, @captured_mcp_types.dup)
    config.instance_variable_set(:@mcp_skills, @captured_mcp_skills.dup)
    config.instance_variable_set(:@servers, @captured_mcp_servers.dup)
    config.catalogs.invalidate!
  end
end

module DummyMcpRegistration
  def mcp_include_endpoints(*names, api: :public)
    names.flatten.each do |name|
      next if RecordingStudioMcp.configuration.tool(name.to_s)

      RecordingStudioMcp.register_tool(
        name: name.to_s,
        endpoint: name,
        title: name.to_s.tr("_", " ").capitalize,
        description: "#{name} named route.",
        input: {},
        output: "the route result"
      )
    end
    rebuild_mcp_server(api, extra: names)
  end

  def mcp_include_metrics(*names, api: :public)
    extras = names.flatten.map(&:to_s).sort
    existing = RecordingStudioMcp.configuration.servers[api.to_s]
    current = Array(existing&.included_tools).map(&:name)
    generics = RecordingStudioMcp::Catalogs::GENERIC_NAMES
    prefix = current.select { |name| generics.include?(name) }
    rest = current - prefix - extras
    rebuild_mcp_server(api, tools: prefix + extras + rest)
  end

  def mcp_register_type(name, api: :public)
    RecordingStudioMcp.register_type(type: name, description: "#{name} records.")
    rebuild_mcp_server(api)
  end

  def rebuild_mcp_server(api, extra: [], tools: nil)
    existing = RecordingStudioMcp.configuration.servers[api.to_s]
    tool_names = tools || (Array(existing&.included_tools).map(&:name) | extra.map(&:to_s))
    skills = Array(existing&.included_skills)
    allow = existing&.allow_sensitive || false
    RecordingStudioMcp.register_server(api, api: api, allow_sensitive: allow) do
      include_tools(*tool_names)
      include_skills(*skills)
    end
  end
end

module ActiveSupport
  class TestCase
    include DummyMcpRegistration
    include DummyMcpIsolation
    setup :capture_mcp_registry
    teardown :restore_mcp_registry
    prepend ConnectionCleanup
  end
end
