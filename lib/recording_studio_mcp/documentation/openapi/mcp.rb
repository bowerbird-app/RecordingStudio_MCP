# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module Mcp
        module_function

        def section(page, group_tags: nil)
          surface = ToolSurface.for(api: page.api_key)
          {
            "protocolVersion" => RecordingStudioMcp.configuration.protocol_version,
            "instructions" => page.instructions.to_s,
            "servers" => Internals.servers(page.api_key),
            "capabilities" => capabilities,
            "tools" => documented_tools(page, surface, group_tags)
          }
        end

        def documented_tools(page, surface, group_tags)
          protocol = page.tools.map { |tool| tool_entry(tool, surface) }
          covered = named_action_keys(surface.server)
          actions = TypeActions.tools(page, group_tags: group_tags, covered: covered).map do |tool|
            tool_entry(tool, surface)
          end
          protocol + actions
        end

        def named_action_keys(server)
          return [] unless server

          server.tools.each_value.filter_map { |tool| named_action_key(server, tool) }
        end

        def named_action_key(server, tool)
          registration = tool.registration
          return if registration.nil? || Catalogs::GENERIC_NAMES.include?(tool.name)
          return unless registration.target.action?
          return unless RecordingStudioApi.lookup(
            api: server.api, recordable_type: registration.type, action: registration.target.value
          )

          [registration.type.to_s, registration.target.value.to_s]
        end

        def capabilities
          resources = RecordingStudioMcp.events_registered? ? { "subscribe" => true } : {}
          {
            "tools" => { "listChanged" => false },
            "resources" => resources
          }
        end

        def tool_entry(tool, surface)
          tool = Internals.stringify(tool)
          entry = {
            "name" => tool.fetch("name"),
            "title" => tool["title"],
            "description" => tool["description"].presence || tool["title"].presence || tool["name"],
            "inputSchema" => Internals.stringify(tool["inputSchema"]) || { "type" => "object" }
          }.compact
          entry["x-mcp-docs-only"] = true if tool["x-mcp-docs-only"]
          entry.merge(ToolDocs.openapi_extras(entry, tool, surface))
        end

        private_class_method :documented_tools, :named_action_keys, :named_action_key, :capabilities, :tool_entry
      end
    end
  end
end
