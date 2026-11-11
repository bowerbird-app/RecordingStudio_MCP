# frozen_string_literal: true

require "json"

module RecordingStudioMcp
  module Documentation
    module Openapi
      module Schemas
        module_function

        def for(page)
          types = page.types.each_with_object({}) do |entry, acc|
            entry = Internals.stringify(entry)
            name = entry["type"].to_s
            next if name.blank?

            acc[name] = type_schema(entry)
          end
          types["TypeName"] = Internals.stringify(page.type_schema)
          types
        end

        def type_schema(entry)
          fields = Array(entry["writable_fields"]).map { |field| Internals.stringify(field) }
          type_object_schema(entry, fields).merge(type_extensions(entry)).compact
        end

        def type_object_schema(entry, fields)
          {
            "type" => "object",
            "title" => entry["type"].to_s,
            "description" => type_description(entry),
            "properties" => type_properties(fields),
            "required" => type_required(fields)
          }
        end

        def type_extensions(entry)
          {
            "x-mcp-operations" => Array(entry["operations"]),
            "x-mcp-capability-actions" => Array(entry["capability_actions"]),
            "x-mcp-parent" => entry["parent"],
            "x-tags" => ["Types"]
          }
        end

        def type_properties(fields)
          fields.each_with_object({}) do |field, acc|
            name = field["name"].to_s
            next if name.blank?

            acc[name] = field_schema(field)
          end
        end

        def type_required(fields)
          fields.select { |field| field["required"] }.map { |field| field["name"].to_s }
        end

        def field_schema(field)
          schema = { "type" => field["type"].presence || "string" }
          schema["description"] = field["description"] if field["description"].present?
          schema["enum"] = field["allowed_values"] if Array(field["allowed_values"]).any?
          schema["readOnly"] = true if field["immutable_on_update"]
          schema
        end

        def type_description(entry)
          [
            "Registered type #{entry['type']}.",
            operations_line(entry),
            writable_line(entry),
            actions_block(entry)
          ].compact.join("\n\n")
        end

        def operations_line(entry)
          operations = Array(entry["operations"]).map(&:to_s).reject(&:blank?).uniq
          return "Allowed operations: none." if operations.empty?

          "Allowed operations: #{operations.join(', ')}."
        end

        def writable_line(entry)
          names = Array(entry["writable_fields"]).filter_map do |field|
            field = Internals.stringify(field)
            field["name"].presence
          end
          return "Writable fields: none." if names.empty?

          "Writable fields: #{names.join(', ')}."
        end

        def actions_block(entry)
          actions = Array(entry["capability_actions"]).map { |action| Internals.stringify(action) }
          return "Enabled capability actions: none." if actions.empty?

          lines = ["Enabled capability actions (run with `capability_action`):"]
          actions.each do |action|
            lines << "- `#{action['name']}`#{action_contract_suffix(action)}"
          end
          lines.join("\n")
        end

        def action_contract_suffix(action)
          params = action["params"]
          return "" if params.blank?

          "\n\n```json\n#{JSON.pretty_generate(params)}\n```"
        end

        private_class_method :type_schema, :type_object_schema, :type_extensions, :type_properties,
                             :type_required, :field_schema, :type_description, :operations_line,
                             :writable_line, :actions_block, :action_contract_suffix
      end
    end
  end
end
