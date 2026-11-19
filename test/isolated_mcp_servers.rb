# frozen_string_literal: true

module IsolatedMcpServers
  def ensure_tree_server(api = :public, extra_tools: [], allow_sensitive: false)
    extras = retained_tool_names(api) | extra_tools.map(&:to_s)
    publish_mcp_server(
      api,
      tools: RecordingStudioMcp::Catalogs::GENERIC_NAMES + extras,
      allow_sensitive: allow_sensitive
    )
  end

  def include_metric_server(api = :public, tree: true)
    catalog = RecordingStudioMcp::Catalog.new(api: api, server: false)
    names = metric_tool_names(catalog)
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

  def include_api_endpoints(api: :public, tree: false, allow_sensitive: false)
    names = advertised_endpoint_names(api)
    names.each do |name|
      next if RecordingStudioMcp.configuration.tool(name)

      register_mcp_endpoint_tool(name, api: api, register_api: false)
    end
    publish_included_endpoints(api, names, tree: tree, allow_sensitive: allow_sensitive)
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

  private

  def metric_tool_names(catalog)
    (
      RecordingStudioMcp::MetricTools.collect_recordable(catalog) +
      RecordingStudioMcp::MetricTools.collect_catalog(catalog, nil)
    ).map { |metric| metric.name.to_s }
  end

  def advertised_endpoint_names(api)
    registry = RecordingStudioApi.configuration.fetch_api(api).registered_endpoint_registry
    registry.all.map { |item| item.name.to_s }.select { |name| advertise_mcp_endpoint_name?(name) }.sort
  end

  def publish_included_endpoints(api, names, tree:, allow_sensitive:)
    if tree
      extras = retained_tool_names(api) | names
      publish_mcp_server(
        api,
        tools: RecordingStudioMcp::Catalogs::GENERIC_NAMES + extras,
        allow_sensitive: allow_sensitive
      )
    else
      publish_mcp_server(api, tools: retained_tool_names(api) | names, allow_sensitive: allow_sensitive)
    end
  end
end
