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
          "Tool: capability_action with type `#{type_name}` and action `#{action_name}`"
        end

        def page_type_names(page)
          Array(page.types).map { |entry| Internals.stringify(entry)["type"].to_s }
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
          type_name = entry["type"].to_s
          action_name = action["name"].to_s
          tagged_tool(
            name: "#{type_name}--#{action_name}",
            title: ActionDocs.title(action_name, api_key, type_name),
            description: page_description(entry, action, api_key),
            tags: ToolDocs.action_tags(type_name, api: api_key, group_tags: group_tags, type_names: type_names),
            input_schema: action_input_schema(action)
          )
        end
        private_class_method :action_tool

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
          compact_description [
            runs_on_line(entry["type"]),
            Schemas.registered_type_description(entry["type"], api_key),
            "Type: `#{entry['type']}`",
            action_summary(action["name"], api_key),
            ActionDocs.raw_copy(RecordingStudioApi.capability_action(action["name"], api: api_key))["description"],
            access_line(action["name"], api_key),
            tool_line(entry["type"], action["name"])
          ]
        end
        private_class_method :page_description

        def compact_description(lines)
          lines.compact.join("\n\n")
        end
        private_class_method :compact_description

        def runs_on_line(type_name)
          label = RecordingStudio.recordable_type_label(type_name)
          "Runs on a #{label} (#{type_name})."
        end
        private_class_method :runs_on_line

        def action_summary(action_name, api_key)
          ActionDocs.raw_copy(RecordingStudioApi.capability_action(action_name, api: api_key))["summary"]
        end
        private_class_method :action_summary

        def access_line(action_name, api_key)
          registered = RecordingStudioApi.capability_action(action_name, api: api_key)
          ActionDocs.access_line(
            RecordingStudioApi.configuration.capability_action_roles.fetch(action_name, registered&.required_role)
          )
        end
        private_class_method :access_line
      end
    end
  end
end
