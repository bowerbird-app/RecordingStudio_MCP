# frozen_string_literal: true

require "test_helper"

class McpCopyTest < Minitest::Test
  NAMES = %w[
    mcp_calls-over_time
    mcp_calls-failed_over_time
    mcp_calls-by_tool
    mcp_calls-failed_by_tool
    mcp_calls-by_method
    mcp_calls-rate_limited
    mcp_subscriptions-failing
  ].freeze

  def test_tool_names_lists_operations_catalog_metrics
    assert_equal NAMES, RecordingStudioMcp::McpCopy.tool_names
  end

  def test_each_tool_maps_identifier_dot_to_hyphenated_name
    RecordingStudioMcp::McpCopy::TOOLS.each do |row|
      identifier = row.fetch(:identifier)
      name = row.fetch(:name)

      assert_equal name, identifier.sub(".", "-")
      assert_equal row, RecordingStudioMcp::McpCopy.for_identifier(identifier)
      assert_equal row, RecordingStudioMcp::McpCopy.for_name(name)
    end
  end

  def test_catalog_tool_fields_use_mcp_copy_not_api_titles
    catalog = Struct.new(:api).new("operations")
    entry = {
      identifier: "mcp_calls.over_time",
      resource: "mcp_calls",
      name: "over_time",
      title: "Calls over time",
      description: "Sum of MCP request counts by day from daily usage rollups.",
      result_type: "timeseries"
    }
    fields = RecordingStudioMcp::MetricTools.send(
      :catalog_tool_fields, catalog, entry, "mcp_calls.over_time"
    )
    copy = RecordingStudioMcp::McpCopy.for_identifier("mcp_calls.over_time")

    assert_equal copy.fetch(:title), fields[:title]
    assert_equal copy.fetch(:description), fields[:description]
    refute_equal "Calls over time", fields[:title]
  end

  def test_dummy_operations_server_includes_mcp_copy_tool_names
    dummy = File.read(File.expand_path("dummy/config/initializers/recording_studio_mcp.rb", __dir__))

    assert_includes dummy, "*RecordingStudioMcp::McpCopy.tool_names"
    refute_includes dummy, '"mcp_calls-over_time"'
    refute_includes dummy, '"mcp_subscriptions-failing"'
  end

  def test_api_metric_copy_stays_plain
    metrics = File.read(File.expand_path("../lib/recording_studio_mcp/metrics.rb", __dir__))

    assert_includes metrics, 'title: "Calls over time"'
    assert_includes metrics, 'title: "Failed calls over time"'
    assert_includes metrics, 'title: "Calls by tool"'
    assert_includes metrics, 'title: "Failed calls by tool"'
    assert_includes metrics, 'title: "Calls by method"'
    assert_includes metrics, 'title: "Rate limited calls"'
    assert_includes metrics, 'title: "Failing event subscriptions"'
    refute_includes metrics, 'title: "MCP calls over time"'
    refute_includes metrics, 'title: "Count MCP calls over time"'
  end
end
