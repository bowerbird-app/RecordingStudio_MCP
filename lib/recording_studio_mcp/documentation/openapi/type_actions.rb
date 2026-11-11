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

          (actions.flat_map { |action| lines(entry, action) } + [runtime_note]).join("\n\n")
        end

        def tool_line(type_name, action_name)
          "Tool: capability_action with type `#{type_name}` and action `#{action_name}`"
        end

        def runtime_note
          "These run through the `capability_action` tool; `describe` lists them at runtime."
        end

        def lines(entry, action)
          [
            "**#{action['name']}**",
            tool_line(entry["type"], action["name"]),
            contract_suffix(action).presence
          ].compact
        end
        private_class_method :lines

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
