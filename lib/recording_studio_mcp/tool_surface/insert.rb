# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    private

    def advertised_endpoints
      return [] unless server

      server.tools.each_value.filter_map do |tool|
        next unless tool.registration&.target&.endpoint?

        RecordingStudioApi.registered_endpoint(tool.registration.target.value, api: catalog.api)
      end
    end

    def insert_describe
      insert(
        Catalogs::DESCRIBE_NAME,
        Entry.new(family: :tree, definition: Tools.describe_tool(catalog))
      )
    end

    def insert_server_tools
      insert_generic_tools
      insert_describe
      return unless server

      server.tools.each_value do |tool|
        next if Catalogs::GENERIC_NAMES.include?(tool.name)

        insert_built_tool(tool)
      end
    end

    def insert_generic_tools
      return unless server

      Catalogs::GENERIC_NAMES.each do |name|
        tool = server.tool(name)
        insert_built_tool(tool) if tool
      end
    end

    def insert_built_tool(tool)
      if tool.metric
        metric = live_metric(tool.name)
        insert(tool.name, metric_entry(metric)) if metric
      elsif tool.registration&.target&.endpoint?
        insert_endpoint_tool(tool)
      elsif Catalogs::GENERIC_NAMES.include?(tool.name)
        insert_generic_tool(tool)
      else
        insert_typed_tool(tool)
      end
    end

    def insert_generic_tool(tool)
      return unless advertise_generic?(tool.name)

      definition = Tools.public_send("#{tool.name}_tool", catalog)
      definition = definition.merge(title: tool.title) if tool.title.present?
      insert(tool.name, Entry.new(family: :tree, definition: definition))
    end

    def advertise_generic?(name)
      return catalog.capability_actions? if name == "capability_action"

      operation = Tools::TREE_OPERATION_TOOLS.key(name)
      operation && catalog.visible_operations.map(&:to_sym).include?(operation)
    end

    def insert_typed_tool(tool)
      definition = Tools.registered_tool(tool, catalog)
      insert(tool.name, Entry.new(family: :tree, definition: definition))
    end

    def insert_endpoint_tool(tool)
      endpoint = advertised_endpoint_for(tool)
      return if endpoint.nil?

      warn_skipped_metric_collision(tool.name)
      insert(tool.name, endpoint_entry_from(tool, endpoint))
    end

    def advertised_endpoint_for(tool)
      endpoint = RecordingStudioApi.registered_endpoint(tool.registration.target.value, api: catalog.api)
      endpoint if endpoint && advertise_endpoint?(endpoint)
    end

    def endpoint_entry_from(tool, endpoint)
      Entry.new(
        family: :endpoint,
        definition: overlay_text(Tools.endpoint_tool(endpoint, api: catalog.api), tool),
        endpoint: endpoint
      )
    end

    def live_metric(name)
      recordable = MetricTools.collect_recordable(catalog)
      recordable = [] if recordable.empty? || !metric_view_allowed?
      (recordable + MetricTools.collect_catalog(catalog, @access_grant)).find { |metric| metric.name.to_s == name }
    end

    def metric_view_allowed?
      return true if @access_grant.nil?

      recording = @access_grant.scope_recording || @access_grant.root_recording
      return false unless @access_grant.respond_to?(:authorized?)

      @access_grant.authorized?(recording: recording, role: :view)
    rescue StandardError
      false
    end

    def overlay_text(definition, tool)
      definition.merge(title: tool.title, description: tool.description)
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
        MetricTools.warn_skipped(key, blocked_metric_reason(key))
        return
      end
      raise RecordingStudioApi::ConfigurationError, duplicate_name_message(key, entry) if @by_name.key?(key)

      @by_name[key] = entry
    end

    def advertise_endpoint?(endpoint)
      name = endpoint.name.to_s
      name.match?(TOOL_NAME) && Tools::TREE_NAMES.exclude?(name)
    end

    def warn_skipped_metric_collision(name)
      return unless live_metric(name)

      MetricTools.warn_skipped(name, "name collides with an endpoint tool")
    end

    def blocked_metric_name?(key)
      Tools::TREE_NAMES.include?(key) || @by_name.key?(key)
    end

    def blocked_metric_reason(key)
      return "name collides with a tree tool" if Tools::TREE_NAMES.include?(key)

      "name collides with an existing tool"
    end

    def duplicate_name_message(name, entry)
      if entry.family == :endpoint
        "Registered endpoint name #{name} collides with an existing tool"
      else
        "Tool #{name} collides with an existing tool"
      end
    end
  end
end
