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

      def mismatches(server)
        server.tools.each_value.filter_map do |tool|
          next unless tool.sensitive
          next if server.allow_sensitive || tool.allow_sensitive == true

          "server #{server.name} tool #{tool.name} is sensitive without allow_sensitive"
        end
      end
    end
  end
end
