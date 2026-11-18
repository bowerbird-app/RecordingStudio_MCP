# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeActions
        module_function

        def tools(page, group_tags: nil)
          type_names = page_type_names(page)
          listed = Array(page.types).flat_map { |entry| tools_for(entry, page.api_key, group_tags, type_names) }
          listed.sort_by { |tool| [tool["title"].to_s, tool["name"].to_s] }
        end

        def tool_line(type_name, action_name)
          "Tool: capability_action with type `#{type_name}` and action `#{action_name}`. " \
            "Pass idempotency_key to return the first result."
        end

        def page_type_names(page)
          Array(page.types).map { |entry| Internals.stringify(entry)["recordable_type"].to_s }
        end
        private_class_method :page_type_names

        def tools_for(entry, api_key, group_tags, type_names)
          entry = Internals.stringify(entry)
          Array(entry["capability_actions"]).map do |action|
            action_tool(entry, Internals.stringify(action), api_key, group_tags, type_names)
          end
        end
        private_class_method :tools_for

        def action_tool(entry, action, api_key, group_tags, type_names)
          shown = entry["type"].to_s
          full_name = entry["recordable_type"].to_s
          action_name = action["name"].to_s
          tagged_tool(
            name: "#{shown}--#{action_name}",
            title: ActionDocs.title(action_name, api_key, full_name),
            description: page_description(entry, action, api_key),
            tags: action_tag_names(full_name, action_name, api_key, group_tags, type_names),
            input_schema: action_input_schema(action)
          )
        end
        private_class_method :action_tool

        def action_tag_names(full_name, action_name, api_key, group_tags, type_names)
          ToolDocs.action_tags(
            full_name,
            api: api_key,
            group_tags: group_tags,
            type_names: type_names,
            tag_suffix: ActionDocs.tag_suffix(action_name, api_key, full_name)
          )
        end
        private_class_method :action_tag_names

        def action_input_schema(action)
          params = action["params"]
          return { "type" => "object" } if params.blank?

          schema = ActionDocs.schema(params)
          schema[:example] = ActionDocs.example(schema[:properties]) if schema[:properties].present?
          Internals.stringify(schema)
        end
        private_class_method :action_input_schema

        def tagged_tool(name:, title:, description:, tags:, input_schema:)
          tool = {
            "name" => name,
            "title" => title,
            "description" => description,
            "inputSchema" => input_schema,
            "x-mcp-docs-only" => true
          }
          tool["tags"] = tags if tags.any?
          tool
        end
        private_class_method :tagged_tool

        def page_description(entry, action, api_key)
          shown = entry["type"].to_s
          full_name = entry["recordable_type"].to_s
          [
            runs_on_line(full_name, shown),
            Schemas.registered_type_description(full_name, api_key),
            "Type: `#{shown}`",
            *action_copy_lines(action, api_key, full_name),
            tool_line(shown, action["name"])
          ].compact.join("\n\n")
        end
        private_class_method :page_description

        def action_copy_lines(action, api_key, type_name)
          registered = RecordingStudioApi.capability_action(action["name"], api: api_key)
          copy = ActionDocs.copy_for(registered, type_name)
          [copy["summary"], copy["description"]]
        end
        private_class_method :action_copy_lines

        def runs_on_line(full_name, shown)
          label = singular_type_label(full_name)
          line = "Runs on #{label} records"
          line = "#{line} (#{shown})" if shown.present? && shown != label
          "#{line}."
        end
        private_class_method :runs_on_line

        def singular_type_label(type_name)
          RecordingStudio.recordable_type_label(type_name).to_s.singularize
        end
        private_class_method :singular_type_label
      end
    end
  end
end
