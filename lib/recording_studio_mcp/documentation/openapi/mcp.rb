# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module Mcp
        RESOURCE_DESCRIPTION = "One Accessible recording as JSON. The id is the recording id."

        module_function

        def section(page)
          {
            "protocolVersion" => RecordingStudioMcp.configuration.protocol_version,
            "instructions" => page.instructions.to_s,
            "servers" => Internals.servers(page.api_key),
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
          tool = Internals.stringify(tool)
          with_optional_fields(base_tool_entry(tool), tool).compact
        end

        def base_tool_entry(tool)
          {
            "name" => tool.fetch("name"),
            "title" => tool["title"],
            "description" => tool["description"].presence || tool["title"].presence || tool["name"],
            "inputSchema" => Internals.stringify(tool["inputSchema"]) || { "type" => "object" }
          }
        end

        def with_optional_fields(entry, tool)
          tags = Array(tool["tags"]).map(&:to_s).reject(&:blank?)
          entry["tags"] = tags if tags.any?
          schema = Internals.stringify(tool["outputSchema"])
          entry["outputSchema"] = schema if schema.present?
          entry
        end

        def resource(template)
          template = Internals.stringify(template)
          {
            "name" => template["name"],
            "description" => RESOURCE_DESCRIPTION,
            "uri" => template["uriTemplate"] || template["uri"],
            "mimeType" => template["mimeType"]
          }.compact
        end

        def resource_template(template)
          template = Internals.stringify(template)
          {
            "name" => template["name"],
            "description" => RESOURCE_DESCRIPTION,
            "uriTemplate" => template["uriTemplate"],
            "mimeType" => template["mimeType"]
          }.compact
        end

        private_class_method :capabilities, :tool_entry, :base_tool_entry, :with_optional_fields,
                             :resource, :resource_template
      end
    end
  end
end
