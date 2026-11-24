# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module ToolIndex
      module_function

      def groups(page)
        spec = Openapi.document(page)
        tools = Array(spec.dig("x-mcp", "tools"))
        buckets = tool_buckets(tools)
        tag_names(spec, tools).filter_map do |name|
          next unless ToolDocs.shown_sidebar_tag?(name, tools: tools)

          [name, buckets[name]]
        end
      end

      def tool_buckets(tools)
        buckets = Hash.new { |hash, key| hash[key] = [] }
        tools.each { |tool| place(tool, buckets) }
        buckets
      end
      private_class_method :tool_buckets

      def tag_names(spec, tools)
        ordered = Array(spec["tags"]).filter_map { |tag| tag["name"].presence }
        extra = tools.flat_map { |tool| Array(tool["tags"]) }
        ToolDocs.sidebar_tag_order(ordered + extra)
      end
      private_class_method :tag_names

      def place(tool, buckets)
        tags = Array(tool["tags"]).presence || [ToolDocs::OTHER_TOOLS_TAG]
        tags.each { |tag| buckets[tag] << tool }
      end
      private_class_method :place
    end
  end
end
