# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeOperationSchema
        module_function

        def for(tool_name, type_name, schema)
          names = kept_names(tool_name, schema)
          built = {
            "type" => "object",
            "properties" => names.to_h { |name| [name, copied_property(schema, name, type_name)] },
            "required" => required(schema) & names
          }
          built["additionalProperties"] = true if writable?(tool_name, schema)
          built
        end

        def kept_names(tool_name, schema)
          props = properties(schema)
          listed = case tool_name
                   when "list" then %w[parent_id]
                   when "create" then %w[parent_id idempotency_key]
                   else %w[id]
                   end
          ["type"] + listed.select { |name| props.include?(name) }
        end
        private_class_method :kept_names

        def copied_property(schema, name, type_name)
          raw = properties(schema).fetch(name) { { "type" => "string" } }
          return raw unless name == "type"

          raw.merge("const" => type_name).except("enum")
        end
        private_class_method :copied_property

        def writable?(tool_name, schema)
          %w[create update].include?(tool_name) && schema["additionalProperties"] == true
        end
        private_class_method :writable?

        def properties(schema)
          schema["properties"] || {}
        end
        private_class_method :properties

        def required(schema)
          Array(schema["required"])
        end
        private_class_method :required
      end
    end
  end
end
