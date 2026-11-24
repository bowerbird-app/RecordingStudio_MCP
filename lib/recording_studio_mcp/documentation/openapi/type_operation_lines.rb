# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeOperationLines
        module_function

        def context_for(page)
          {
            api_key: page.api_key,
            schemas: Tools.definitions(api: page.api_key).each_with_object({}) do |tool, schemas|
              schemas[tool[:name]] = Internals.stringify(tool[:inputSchema] || {})
            end
          }
        end

        def section_for(entry, shown, context)
          shown_entry = Internals.stringify(entry)
          [
            shown_entry["description"],
            *lines_for(shown_entry, shown, context),
            TypeDescribeBlocks.capability_actions_block(shown_entry, context[:api_key]),
            TypeDescribeBlocks.parent_block(shown_entry),
            TypeDescribeBlocks.relationships_block(shown_entry)
          ].compact.reject(&:blank?).join("\n\n")
        end

        def lines_for(entry, shown, context)
          Array(entry["tools"]).filter_map do |name|
            line_for_tool(name.to_s, shown, Internals.stringify(entry), context)
          end
        end

        def line_for_tool(name, type_name, entry, context)
          if Tools::TREE_OPERATION_TOOLS.value?(name)
            tool_line(name, type_name, context[:schemas].fetch(name, {}), entry, context)
          elsif name == "capability_action"
            "Tool: capability_action with type `#{type_name}`."
          else
            "Tool: #{name}"
          end
        end
        private_class_method :line_for_tool

        def tool_line(tool_name, type_name, schema, entry, context)
          "Tool: #{tool_name} with #{joined(argument_parts(tool_name, type_name, schema, entry, context))}"
        end

        def argument_parts(tool_name, type_name, schema, entry, context)
          case tool_name
          when "list" then list_parts(type_name, schema, entry)
          when "create" then create_parts(type_name, schema, entry, context)
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

        def create_parts(type_name, schema, entry, context)
          props = properties(schema)
          parts = ["type `#{type_name}`"]
          parts << "parent_id" if props.include?("parent_id") && !TypeDescribeBlocks.server_parent?(entry, context)
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
