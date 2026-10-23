# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    private

    def advertised_endpoints(catalog)
      Array(catalog.registered_endpoints).sort_by { |endpoint| endpoint.name.to_s }.select do |endpoint|
        advertise_endpoint?(endpoint)
      end
    end

    def advertise_endpoint?(endpoint)
      name = endpoint.name.to_s
      name.match?(TOOL_NAME) && Tools::TREE_NAMES.exclude?(name)
    end

    def insert_tree_tools
      return unless tree_enabled?

      Tools.tree_definitions(catalog).each do |definition|
        insert(definition.fetch(:name), Entry.new(family: :tree, definition: definition))
      end
    end

    def insert_metric_tools
      recordable = MetricTools.collect_recordable(catalog)
      recordable = [] if recordable.empty? || !metric_view_allowed?
      catalog_metrics = MetricTools.collect_catalog(catalog, @access_grant)
      (recordable + catalog_metrics).each do |metric|
        insert(metric.name.to_s, metric_entry(metric))
      end
    end

    def metric_view_allowed?
      return true if @access_grant.nil?

      recording = @access_grant.scope_recording || @access_grant.root_recording
      @access_grant.authorized?(recording: recording, role: :view)
    end

    def insert_endpoint_tools
      @endpoints.each do |endpoint|
        insert(endpoint.name.to_s, endpoint_entry(endpoint))
      end
    end

    def metric_entry(metric)
      Entry.new(
        family: :metric,
        definition: Tools.metric_tool(metric),
        metric: metric
      )
    end

    def endpoint_entry(endpoint)
      Entry.new(
        family: :endpoint,
        definition: Tools.endpoint_tool(endpoint, api: catalog.api),
        endpoint: endpoint
      )
    end

    def insert(name, entry)
      key = name.to_s
      if metric_family?(entry) && blocked_metric_name?(key)
        warn_skipped_tool(key, blocked_metric_reason(key))
        return
      end
      if entry.family != :tree && Tools::TREE_NAMES.include?(key)
        raise RecordingStudioApi::ConfigurationError, reserved_name_message(key, entry)
      end
      raise RecordingStudioApi::ConfigurationError, duplicate_name_message(key, entry) if @by_name.key?(key)

      @by_name[key] = entry
    end

    def blocked_metric_name?(key)
      Tools::TREE_NAMES.include?(key) || endpoint_name?(key) || @by_name.key?(key)
    end

    def endpoint_name?(key)
      @endpoints.any? { |endpoint| endpoint.name.to_s == key }
    end

    def blocked_metric_reason(key)
      return "name collides with a tree tool" if Tools::TREE_NAMES.include?(key)
      return "name collides with an endpoint tool" if endpoint_name?(key)

      "name collides with an existing tool"
    end

    def warn_skipped_tool(name, reason)
      MetricTools.warn_skipped(name, reason)
    end

    def reserved_name_message(name, entry)
      return "Registered endpoint names collide with tree tools: #{name}" if entry.family == :endpoint

      "Recordable metric tool #{name} collides with a tree tool"
    end

    def duplicate_name_message(name, entry)
      if entry.family == :endpoint
        "Registered endpoint name #{name} collides with an existing tool"
      else
        "Recordable metric tool #{name} collides with an existing tool"
      end
    end
  end
end
