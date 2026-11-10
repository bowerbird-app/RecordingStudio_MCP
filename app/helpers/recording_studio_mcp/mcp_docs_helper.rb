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
      request.path.chomp("/").delete_suffix("/fullscreen")
    end
  end
end
