# frozen_string_literal: true

module RecordingStudioMcp
  # MCP titles and descriptions for this gem's operations catalog metrics.
  # Hosts include them with `include_tools(*RecordingStudioMcp::McpCopy.tool_names)`.
  # Hyphenated names still work. HTTP API copy stays on Metrics.register.
  module McpCopy
    TOOLS = [
      {
        identifier: "mcp_calls.over_time",
        name: "mcp_calls-over_time",
        title: "Count MCP calls over time",
        description: "Daily totals of MCP requests from usage rollups. Pass from and to. " \
                     "Interval can be day, week, month, or year."
      },
      {
        identifier: "mcp_calls.failed_over_time",
        name: "mcp_calls-failed_over_time",
        title: "Count failed MCP calls over time",
        description: "Failed MCP requests by day from usage rollups. Pass from and to. " \
                     "Interval can be day, week, month, or year."
      },
      {
        identifier: "mcp_calls.by_tool",
        name: "mcp_calls-by_tool",
        title: "Break down MCP calls by tool",
        description: "tools/call counts grouped by tool name. There is no date window."
      },
      {
        identifier: "mcp_calls.failed_by_tool",
        name: "mcp_calls-failed_by_tool",
        title: "Break down failed MCP calls by tool",
        description: "Failed tools/call counts grouped by tool name from daily usage rollups."
      },
      {
        identifier: "mcp_calls.by_method",
        name: "mcp_calls-by_method",
        title: "Break down MCP calls by method",
        description: "MCP request counts grouped by JSON-RPC method."
      },
      {
        identifier: "mcp_calls.rate_limited",
        name: "mcp_calls-rate_limited",
        title: "Count rate limited MCP calls",
        description: "How many MCP requests hit the rate limit."
      },
      {
        identifier: "mcp_subscriptions.failing",
        name: "mcp_subscriptions-failing",
        title: "Count failing MCP event subscriptions",
        description: "Active, unexpired event subscriptions whose last callback failed. " \
                     "They go inactive after 5 failures in a row."
      }
    ].map(&:freeze).freeze

    BY_IDENTIFIER = TOOLS.to_h { |row| [row.fetch(:identifier), row] }.freeze
    BY_NAME = TOOLS.to_h { |row| [row.fetch(:name), row] }.freeze

    module_function

    def tool_names
      TOOLS.map { |row| row.fetch(:name) }.freeze
    end

    def for_identifier(identifier)
      BY_IDENTIFIER[identifier.to_s]
    end

    def for_name(name)
      BY_NAME[name.to_s]
    end
  end
end
