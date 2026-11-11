# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module Schemas
        module_function

        def for(page, group_tags: nil)
          types_by_name = indexed_types(page)
          schemas = types_by_name.transform_values do |entry|
            type_schema(entry, page.api_key, group_tags: group_tags, types_by_name: types_by_name)
          end
          schemas.merge("TypeName" => Internals.stringify(page.type_schema))
        end

        def indexed_types(page)
          page.types.each_with_object({}) do |entry, acc|
            entry = Internals.stringify(entry)
            name = entry["type"].to_s
            acc[name] = entry if name.present?
          end
        end

        def type_schema(entry, api_key, group_tags: nil, types_by_name: {})
          fields = Array(entry["writable_fields"]).map { |field| Internals.stringify(field) }
          type_object_schema(entry, fields, api_key).merge(
            type_extensions(entry, api_key, group_tags: group_tags, types_by_name: types_by_name)
          ).compact
        end

        def type_object_schema(entry, fields, api_key)
          {
            "type" => "object",
            "title" => RecordingStudio.recordable_type_label(entry["type"]),
            "description" => type_description(entry, api_key),
            "properties" => type_properties(fields),
            "required" => type_required(fields)
          }
        end

        def type_extensions(entry, api_key, group_tags: nil, types_by_name: {})
          {
            "x-mcp-operations" => Array(entry["operations"]),
            "x-mcp-capability-actions" => TypeActions.documented(entry),
            "x-mcp-parent" => entry["parent"],
            "x-tags" => SchemaSidebar.tags(entry, api_key, group_tags, types_by_name).presence
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

        def type_description(entry, api_key)
          [
            type_summary(entry, api_key),
            "Type: `#{entry['type']}`",
            operations_line(entry),
            writable_line(entry),
            TypeActions.block(entry)
          ].compact.join("\n\n")
        end

        def type_summary(entry, api_key)
          registered_type_description(entry["type"], api_key).presence ||
            "A #{RecordingStudio.recordable_type_label(entry['type']).downcase} record in this workspace."
        end

        def registered_type_description(type_name, api_key)
          openapi = RecordingStudioApi.recordable_registration_for(type_name, api: api_key)&.openapi
          return unless openapi.is_a?(Hash)

          openapi[:description].presence || openapi.dig(:tag, :description).presence
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

        private_class_method :indexed_types, :type_schema, :type_object_schema, :type_extensions,
                             :type_properties, :type_required, :field_schema, :type_description,
                             :type_summary, :registered_type_description
      end

      module SchemaSidebar
        module_function

        def tags(entry, api_key, group_tags, types_by_name)
          return [] if hide?(entry, types_by_name)

          ToolDocs.type_tags(entry["type"], api: api_key, group_tags: group_tags)
        end

        def hide?(entry, types_by_name)
          return false if Array(entry["capability_actions"]).empty?

          Array(entry.dig("parent", "allowed_parent_types")).any? do |parent_name|
            nested_parent?(parent_name, types_by_name)
          end
        end

        def nested_parent?(parent_name, types_by_name)
          parent_name = parent_name.to_s
          return false if parent_name.blank?

          parent_entry = types_by_name[parent_name]
          return parent_entry.dig("parent", "root") == false if parent_entry

          declared_non_root?(parent_name)
        end

        def declared_non_root?(parent_name)
          declaration = RecordingStudio.recordable_declaration_for(parent_name)
          declaration.present? && !declaration.root?
        end

        private_class_method :hide?, :nested_parent?, :declared_non_root?
      end
      private_constant :SchemaSidebar
    end
  end
end
