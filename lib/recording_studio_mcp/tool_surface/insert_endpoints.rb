# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    module InsertEndpoints
      private

      def advertised_endpoints
        return [] unless server

        server.tools.each_value.filter_map do |tool|
          next unless tool.registration&.target&.endpoint?

          RecordingStudioApi.registered_endpoint(tool.registration.target.value, api: catalog.api)
        end
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
        definition = Tools.endpoint_tool(endpoint, api: catalog.api, copy: tool.registration.input)
        Entry.new(family: :endpoint, definition: overlay_text(definition, tool), endpoint: endpoint)
      end

      def overlay_text(definition, tool)
        SchemaFromContract.overlay_tool(definition, title: tool.title, description: tool.description)
      end

      def endpoint_entry(endpoint)
        Entry.new(
          family: :endpoint,
          definition: Tools.endpoint_tool(endpoint, api: catalog.api),
          endpoint: endpoint
        )
      end

      def advertise_endpoint?(endpoint)
        name = endpoint.name.to_s
        name.match?(TOOL_NAME) && Tools::TREE_NAMES.exclude?(name)
      end
    end
  end
end
