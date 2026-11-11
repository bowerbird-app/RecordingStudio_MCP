# frozen_string_literal: true

require "json"

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeActions
        module_function

        def documented(entry)
          Array(entry["capability_actions"]).map do |action|
            action = Internals.stringify(action)
            action.merge("description" => tool_line(entry["type"], action["name"]))
          end
        end

        def block(entry)
          actions = Array(entry["capability_actions"]).map { |action| Internals.stringify(action) }
          return "Enabled capability actions: none." if actions.empty?

          "Enabled capability actions appear as tools in this sidebar group."
        end

        def tools(page, group_tags: nil)
          listed = Array(page.types).flat_map { |entry| tools_for(entry, page.api_key, group_tags) }
          listed.sort_by { |tool| [tool["title"].to_s, tool["name"].to_s] }
        end

        def tool_line(type_name, action_name)
          "Tool: capability_action with type `#{type_name}` and action `#{action_name}`"
        end

        def tools_for(entry, api_key, group_tags)
          entry = Internals.stringify(entry)
          Array(entry["capability_actions"]).map do |action|
            action_tool(entry, Internals.stringify(action), api_key, group_tags)
          end
        end
        private_class_method :tools_for

        def action_tool(entry, action, api_key, group_tags)
          type_name = entry["type"].to_s
          action_name = action["name"].to_s
          tagged_tool(
            name: "#{type_name}--#{action_name}",
            title: action_name.humanize.titleize,
            description: page_description(entry, action, api_key),
            tags: ToolDocs.type_tags(type_name, api: api_key, group_tags: group_tags),
            input_schema: action_input_schema(action)
          )
        end
        private_class_method :action_tool

        def action_input_schema(action)
          params = action["params"]
          return { "type" => "object" } if params.blank?

          JSON.parse(JSON.generate(params))
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
          [
            runs_on_line(entry["type"]),
            "Type: `#{entry['type']}`",
            Schemas.operations_line(entry),
            Schemas.writable_line(entry),
            action_summary(action["name"], api_key),
            tool_line(entry["type"], action["name"]),
            contract_suffix(action).presence
          ].compact.join("\n\n")
        end
        private_class_method :page_description

        def runs_on_line(type_name)
          label = RecordingStudio.recordable_type_label(type_name)
          "Runs on a #{label} (#{type_name})."
        end
        private_class_method :runs_on_line

        def action_summary(action_name, api_key)
          openapi = RecordingStudioApi.capability_action(action_name, api: api_key)&.openapi
          return unless openapi.is_a?(Hash)

          openapi[:summary].presence
        end
        private_class_method :action_summary

        def contract_suffix(action)
          params = action["params"]
          return "" if params.blank?

          "```json\n#{JSON.pretty_generate(params)}\n```"
        end
        private_class_method :contract_suffix
      end
    end
  end
end
