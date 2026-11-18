# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeOperations
        TOOLS = {
          "index" => "list",
          "show" => "show",
          "create" => "create",
          "update" => "update",
          "destroy" => "delete"
        }.freeze

        module_function

        def tools(page, group_tags: nil)
          context = build_context(page, group_tags)
          listed = Array(page.types).flat_map { |entry| tools_for(Internals.stringify(entry), context) }
          listed.sort_by { |tool| [tool["title"].to_s, tool["name"].to_s] }
        end

        def build_context(page, group_tags)
          {
            api_key: page.api_key,
            group_tags: group_tags,
            type_names: page_type_names(page),
            catalog: Catalog.new(api: page.api_key),
            schemas: tool_schemas(page.api_key)
          }
        end
        private_class_method :build_context

        def page_type_names(page)
          Array(page.types).map { |entry| Internals.stringify(entry)["recordable_type"].to_s }
        end
        private_class_method :page_type_names

        def tool_schemas(api_key)
          Tools.definitions(api: api_key).each_with_object({}) do |tool, schemas|
            schemas[tool[:name]] = Internals.stringify(tool[:inputSchema] || {})
          end
        end
        private_class_method :tool_schemas

        def tools_for(entry, context)
          shown = entry["type"].to_s
          full_name = entry["recordable_type"].to_s
          tool_names_for(context[:catalog], full_name).map do |tool_name|
            operation_tool(entry, shown, full_name, tool_name, context)
          end
        end
        private_class_method :tools_for

        def tool_names_for(catalog, full_name)
          TOOLS.filter_map do |operation, tool_name|
            tool_name if catalog.type_names_for(operation).include?(full_name)
          end
        end
        private_class_method :tool_names_for

        def operation_tool(entry, shown, full_name, tool_name, context)
          schema = context[:schemas].fetch(tool_name, {})
          line = TypeOperationLines.tool_line(tool_name, shown, schema, entry)
          {
            "name" => "#{shown}--#{tool_name}",
            "title" => operation_title(full_name, tool_name),
            "description" => page_description(full_name, shown, context[:api_key], line),
            "inputSchema" => TypeOperationSchema.for(tool_name, shown, schema),
            "tags" => tags_for(full_name, context),
            "x-mcp-docs-only" => true
          }
        end
        private_class_method :operation_tool

        def operation_title(full_name, tool_name)
          label = RecordingStudio.recordable_type_label(full_name).to_s.singularize
          "#{label} - #{tool_name.to_s.humanize.titleize}"
        end
        private_class_method :operation_title

        def tags_for(full_name, context)
          ToolDocs.action_tags(
            full_name,
            api: context[:api_key],
            group_tags: context[:group_tags],
            type_names: context[:type_names]
          )
        end
        private_class_method :tags_for

        def page_description(full_name, shown, api_key, line)
          [
            runs_on_line(full_name, shown),
            Schemas.registered_type_description(full_name, api_key),
            "Type: `#{shown}`",
            line
          ].compact.join("\n\n")
        end
        private_class_method :page_description

        def runs_on_line(full_name, shown)
          label = RecordingStudio.recordable_type_label(full_name).to_s.singularize
          line = "Runs on #{label} records"
          line = "#{line} (#{shown})" if shown.present? && shown != label
          "#{line}."
        end
        private_class_method :runs_on_line
      end
    end
  end
end
