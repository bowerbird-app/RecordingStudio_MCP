# frozen_string_literal: true

module RecordingStudioMcp
  class Catalogs
    module Audit
      module_function

      def lines(server)
        ["server #{server.name} api=#{server.api} allow_sensitive=#{server.allow_sensitive}"] +
          tool_lines(server) +
          ["types #{server.type_names.join(', ').presence || '(none)'}",
           "skills #{server.skill_names.join(', ').presence || '(none)'}"]
      end

      def tool_lines(server)
        (["describe"] + server.tools.keys).uniq.map do |name|
          tool = server.tool(name)
          sensitive = name == "describe" ? false : tool.sensitive
          "  tool #{name} sensitive=#{sensitive}"
        end
      end

      def assert_sensitive!(server, included, name, sensitive)
        message = sensitive_mismatch(server, included, name, sensitive)
        raise RecordingStudioApi::ConfigurationError, message if message
      end

      def mismatches(server)
        server.tools.each_value.filter_map do |tool|
          sensitive_mismatch(server, tool, tool.name, tool.sensitive)
        end
      end

      def sensitive_mismatch(server, included, name, sensitive)
        return unless sensitive
        return if server.allow_sensitive || included.allow_sensitive == true

        "MCP server #{server.name} includes sensitive tool #{name} without allow_sensitive"
      end
    end
  end
end
