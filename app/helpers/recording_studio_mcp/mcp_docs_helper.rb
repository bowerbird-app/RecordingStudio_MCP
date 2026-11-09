# frozen_string_literal: true

module RecordingStudioMcp
  module McpDocsHelper
    def mcp_docs_json(value)
      return "" if value.nil?

      JSON.pretty_generate(JSON.parse(value.to_json))
    rescue JSON::ParserError, TypeError
      value.to_s
    end
  end
end
