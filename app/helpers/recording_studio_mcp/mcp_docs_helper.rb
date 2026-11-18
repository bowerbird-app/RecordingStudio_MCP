# frozen_string_literal: true

module RecordingStudioMcp
  module McpDocsHelper
    def mcp_docs_spec_path
      "#{docs_mount_path}/openapi.json"
    end

    def mcp_docs_redoc_path
      "#{docs_mount_path}/redoc.js"
    end

    def docs_mount_path
      request.path.chomp("/")
    end

    def docs_root_path
      docs_mount_path.delete_suffix("/fullscreen")
    end

    def mcp_docs_tool_groups
      return [] unless @page

      Documentation::ToolIndex.groups(@page)
    end
  end
end
