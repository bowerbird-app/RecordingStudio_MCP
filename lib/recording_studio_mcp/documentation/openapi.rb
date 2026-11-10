# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      OPENAPI_VERSION = "3.1.0"
      RESOURCE_DESCRIPTION = "One Accessible recording as JSON. The id is the recording id."

      module_function

      def document(page)
        {
          "openapi" => OPENAPI_VERSION,
          "info" => info(page),
          "servers" => servers(page.api_key),
          "paths" => {},
          "components" => { "schemas" => schemas(page) },
          "x-mcp" => mcp(page)
        }
      end

      def info(page)
        {
          "title" => page.title,
          "version" => RecordingStudioMcp::VERSION,
          "description" => page.instructions.to_s
        }
      end

      def servers(api_key)
        [{ "url" => NamedApi.mcp_path(api_key), "description" => "Streamable HTTP MCP" }]
      end

      def mcp(page)
        {
          "protocolVersion" => RecordingStudioMcp.configuration.protocol_version,
          "instructions" => page.instructions.to_s,
          "servers" => servers(page.api_key),
          "capabilities" => capabilities,
          "tools" => page.tools.map { |tool| tool_entry(tool) },
          "resources" => [resource(page.resource_template)],
          "resourceTemplates" => [resource_template(page.resource_template)]
        }
      end

      def capabilities
        resources = RecordingStudioMcp.events_registered? ? { "subscribe" => true } : {}
        {
          "tools" => { "listChanged" => false },
          "resources" => resources
        }
      end

      def tool_entry(tool)
        tool = stringify(tool)
        {
          "name" => tool.fetch("name"),
          "title" => tool["title"],
          "description" => tool["description"].presence || tool["title"].presence || tool["name"],
          "inputSchema" => stringify(tool["inputSchema"]) || { "type" => "object" }
        }.compact
      end

      def resource(template)
        template = stringify(template)
        {
          "name" => template["name"],
          "description" => RESOURCE_DESCRIPTION,
          "uri" => template["uriTemplate"] || template["uri"],
          "mimeType" => template["mimeType"]
        }.compact
      end

      def resource_template(template)
        template = stringify(template)
        {
          "name" => template["name"],
          "description" => RESOURCE_DESCRIPTION,
          "uriTemplate" => template["uriTemplate"],
          "mimeType" => template["mimeType"]
        }.compact
      end

      def schemas(page)
        types = page.types.each_with_object({}) do |entry, acc|
          entry = stringify(entry)
          name = entry["type"].to_s
          next if name.blank?

          acc[name] = type_schema(entry)
        end
        types["TypeName"] = stringify(page.type_schema)
        types
      end

      def type_schema(entry)
        fields = Array(entry["writable_fields"]).map { |field| stringify(field) }
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
        operations = Array(entry["operations"]).join(", ").presence || "none"
        "Registered type #{entry['type']}. Operations: #{operations}."
      end

      def stringify(value)
        return value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)
        return value.as_json if value.respond_to?(:as_json)

        value
      end
      private_class_method :info, :servers, :mcp, :capabilities, :tool_entry, :resource,
                           :resource_template, :schemas, :type_schema, :type_object_schema,
                           :type_extensions, :type_properties, :type_required, :field_schema,
                           :type_description, :stringify
    end
  end
end
