# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeOperationLines
        module_function

        def context_for(page)
          {
            catalog: Catalog.new(api: page.api_key),
            schemas: Tools.definitions(api: page.api_key).each_with_object({}) do |tool, schemas|
              schemas[tool[:name]] = Internals.stringify(tool[:inputSchema] || {})
            end
          }
        end

        def lines_for(entry, shown, full_name, context)
          Tools::TREE_OPERATION_TOOLS.filter_map do |operation, tool_name|
            next unless context[:catalog].type_names_for(operation).include?(full_name)

            tool_line(tool_name, shown, context[:schemas].fetch(tool_name, {}), entry)
          end
        end

        def capability_line(type_name, action_name, include_idempotency_key:)
          line = "Tool: capability_action with type `#{type_name}` and action `#{action_name}`."
          return line unless include_idempotency_key

          "#{line} Pass idempotency_key to replay an action flagged creates: true when the input matches. " \
            "A different input for that key is an error."
        end

        def replays?(action_name, recordable_type, api_key)
          action = RecordingStudioApi.capability_action(action_name, api: api_key)
          return false if action.nil?
          return true if action.creates?

          registration = RecordingStudioApi.resource_handler_registration(
            recordable_type, action.name, api: api_key
          )
          registration.respond_to?(:creates?) && registration.creates?
        end

        def tool_line(tool_name, type_name, schema, entry)
          "Tool: #{tool_name} with #{joined(argument_parts(tool_name, type_name, schema, entry))}"
        end

        def argument_parts(tool_name, type_name, schema, entry)
          case tool_name
          when "list" then list_parts(type_name, schema, entry)
          when "create" then create_parts(type_name, schema)
          when "update" then update_parts(type_name, schema)
          else id_parts(type_name, schema)
          end
        end
        private_class_method :argument_parts

        def list_parts(type_name, schema, entry)
          parts = ["type `#{type_name}`"]
          return parts unless properties(schema).include?("parent_id")

          hint = parent_hint(entry)
          parts << (hint ? "parent_id (#{hint})" : "parent_id")
        end
        private_class_method :list_parts

        def create_parts(type_name, schema)
          props = properties(schema)
          parts = ["type `#{type_name}`"]
          parts << "parent_id" if props.include?("parent_id")
          parts << "writable fields at the top level" if schema["additionalProperties"]
          parts << idempotency_part(schema) if props.include?("idempotency_key")
          parts
        end
        private_class_method :create_parts

        def update_parts(type_name, schema)
          parts = id_parts(type_name, schema)
          parts << "writable fields" if schema["additionalProperties"]
          parts
        end
        private_class_method :update_parts

        def id_parts(type_name, schema)
          parts = ["type `#{type_name}`"]
          parts << "id" if properties(schema).include?("id")
          parts
        end
        private_class_method :id_parts

        def idempotency_part(schema)
          return "idempotency_key" if required(schema).include?("idempotency_key")

          "optional idempotency_key"
        end
        private_class_method :idempotency_part

        def parent_hint(entry)
          parents = Array(entry.dig("parent", "allowed_parent_types"))
          return unless parents.one?

          "the #{parents.first.to_s.underscore.humanize.downcase} id"
        end
        private_class_method :parent_hint

        def properties(schema)
          schema["properties"] || {}
        end
        private_class_method :properties

        def required(schema)
          Array(schema["required"])
        end
        private_class_method :required

        def joined(parts)
          return parts.first.to_s if parts.one?
          return "#{parts[0]} and #{parts[1]}" if parts.size == 2

          "#{parts[0..-2].join(', ')}, and #{parts.last}"
        end
        private_class_method :joined
      end
    end
  end
end
