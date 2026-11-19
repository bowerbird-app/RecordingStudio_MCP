# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    include InsertMetrics
    include InsertEndpoints

    private

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
      definition = SchemaFromContract.overlay_tool(
        definition,
        title: tool.title,
        description: overlay_description(tool)
      )
      copy = tool.registration&.input || {}
      SchemaFromContract.overlay_copy(definition[:inputSchema][:properties], copy)
      insert(tool.name, Entry.new(family: :tree, definition: definition))
    end

    def overlay_description(tool)
      stock = GenericTools::DEFINITIONS.find { |item| item.fetch(:name) == tool.name }
      return if stock && tool.description == stock[:description]

      tool.description
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

    def insert(name, entry)
      key = name.to_s
      if metric_family?(entry) && blocked_metric_name?(key)
        MetricTools.warn_skipped(key, blocked_metric_reason(key))
        return
      end
      raise RecordingStudioApi::ConfigurationError, duplicate_name_message(key, entry) if @by_name.key?(key)

      @by_name[key] = entry
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
