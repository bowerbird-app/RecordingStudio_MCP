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
            action.merge("description" => note(entry["type"], action["name"]))
          end
        end

        def block(entry)
          actions = Array(entry["capability_actions"]).map { |action| Internals.stringify(action) }
          return "Enabled capability actions: none." if actions.empty?

          (["Enabled capability actions:"] + actions.flat_map { |action| lines(entry, action) }).join("\n")
        end

        def note(type_name, action_name)
          "Capability action. Call it through the `capability_action` tool with type `#{type_name}` " \
            "and action `#{action_name}`. `describe` lists it at runtime."
        end

        def lines(entry, action)
          [
            "- `#{action['name']}`",
            note(entry["type"], action["name"]),
            contract_suffix(action).presence
          ].compact
        end
        private_class_method :lines

        def contract_suffix(action)
          params = action["params"]
          return "" if params.blank?

          "\n\n```json\n#{JSON.pretty_generate(params)}\n```"
        end
        private_class_method :contract_suffix
      end
    end
  end
end
