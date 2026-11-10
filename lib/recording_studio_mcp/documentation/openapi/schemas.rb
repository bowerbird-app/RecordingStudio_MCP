# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module Schemas
        module_function

        def for(page)
          types = page.types.each_with_object({}) do |entry, acc|
            entry = Openapi.stringify(entry)
            name = entry["type"].to_s
            next if name.blank?

            acc[name] = type_schema(entry)
          end
          types["TypeName"] = Openapi.stringify(page.type_schema)
          types
        end

        def type_schema(entry)
          fields = Array(entry["writable_fields"]).map { |field| Openapi.stringify(field) }
          type_object_schema(entry, fields).merge(type_extensions(entry, fields)).compact
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

        def type_extensions(entry, fields)
          {
            "x-mcp-writable-fields" => fields,
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
          operations = Array(entry["operations"]).join(", ").presence || "none"
          "Registered type #{entry['type']}. Operations: #{operations}."
        end

        private_class_method :type_schema, :type_object_schema, :type_extensions, :type_properties,
                             :type_required, :field_schema, :type_description
      end
    end
  end
end
