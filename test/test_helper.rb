# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require_relative "recordable_metric_tool_helpers"
require "minitest/autorun"
require "rails"
require "active_support/time"
Time.zone ||= "UTC"
require "recording_studio_mcp"

module IsolatedApiConfiguration
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

  def register_tree_type(name = "Page", api: :public, operations: %i[index show create update],
                         capability_actions: nil, openapi: nil, description: nil)
    attrs = {
      api: api,
      serializer: ->(*) { { title: "Title" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      operations: operations
    }
    attrs[:capability_actions] = capability_actions if capability_actions
    attrs[:openapi] = openapi if openapi
    RecordingStudioApi.register_recordable_type_api(name, **attrs)
    RecordingStudioMcp.register_type(type: name, description: description.to_s)
    ensure_tree_server(api)
  end

  def ensure_tree_server(api = :public, extra_tools: [])
    extras = retained_tool_names(api) | extra_tools.map(&:to_s)
    publish_mcp_server(api, tools: RecordingStudioMcp::Catalogs::GENERIC_NAMES + extras)
  end

  def include_metric_server(api = :public, tree: true)
    catalog = RecordingStudioMcp::Catalog.new(api: api, server: false)
    names = (
      RecordingStudioMcp::MetricTools.collect_recordable(catalog) +
      RecordingStudioMcp::MetricTools.collect_catalog(catalog, nil)
    ).map { |metric| metric.name.to_s }
    RecordingStudioApi.configuration.fetch_api(api).recordable_registry.to_h.each_key do |type|
      RecordingStudioMcp.register_type(type: type, description: "#{type} records.")
    end
    kept = endpoint_tool_names(api)
    if tree
      ensure_tree_server(api, extra_tools: names + kept)
    else
      publish_mcp_server(api, tools: kept | names)
    end
  end

  def include_api_endpoints(api: :public, tree: false, allow_sensitive: nil)
    registry = RecordingStudioApi.configuration.fetch_api(api).registered_endpoint_registry
    names = registry.all.map { |item| item.name.to_s }
    names.select! { |name| advertise_mcp_endpoint_name?(name) }
    names.sort!
    names.each do |name|
      next if RecordingStudioMcp.configuration.tool(name)

      register_mcp_endpoint_tool(name, api: api, register_api: false)
    end
    sensitive = allow_sensitive.nil? ? api.to_s == "operations" : allow_sensitive
    if tree
      extras = retained_tool_names(api) | names
      publish_mcp_server(
        api,
        tools: RecordingStudioMcp::Catalogs::GENERIC_NAMES + extras,
        allow_sensitive: sensitive
      )
    else
      publish_mcp_server(api, tools: retained_tool_names(api) | names, allow_sensitive: sensitive)
    end
  end

  def publish_mcp_server(api = :public, tools: [], skills: [], allow_sensitive: false)
    RecordingStudioMcp.register_server(api, api: api, allow_sensitive: allow_sensitive) do
      include_tools(*tools.map(&:to_s).uniq)
      include_skills(*skills.map(&:to_s))
    end
  end

  def advertise_mcp_endpoint_name?(name)
    name.match?(RecordingStudioMcp::ToolSurface::TOOL_NAME) &&
      RecordingStudioMcp::Tools::TREE_NAMES.exclude?(name)
  end

  def retained_tool_names(api = :public)
    existing = Array(RecordingStudioMcp.configuration.servers[api.to_s]&.included_tools).map(&:name)
    existing - RecordingStudioMcp::Catalogs::GENERIC_NAMES
  end

  def endpoint_tool_names(api = :public)
    retained_tool_names(api).select do |name|
      RecordingStudioMcp.configuration.tool(name)&.target&.endpoint?
    end
  end

  def register_mcp_endpoint_tool(name, api: :public, register_api: true, **)
    RecordingStudioApi.register_endpoint(name, api: api, **) if register_api
    return if RecordingStudioMcp.configuration.tool(name.to_s)

    RecordingStudioMcp.register_tool(
      name: name.to_s,
      endpoint: name,
      title: name.to_s.tr("_", " ").capitalize,
      description: "#{name} named route.",
      input: {},
      output: "the route result"
    )
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
