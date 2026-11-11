# frozen_string_literal: true

require "test_helper"

class ToolDocsTest < Minitest::Test
  def test_metric_group_tags_keep_common_acronyms_uppercase
    docs = RecordingStudioMcp::ToolDocs

    assert_equal "AI Runs", docs.humanize_metric_group("ai_runs")
    assert_equal "API Keys", docs.humanize_metric_group("api_keys")
    assert_equal "MCP Calls", docs.humanize_metric_group("mcp_calls")
    assert_equal ["AI Runs"], docs.metric_tags("ai_runs-total")
    assert_equal ["API Keys"], docs.metric_tags("api_keys-created_over_time")
    assert_equal ["MCP Calls"], docs.metric_tags("mcp_calls-over_time")
    assert_equal ["Folders"], docs.metric_tags("folders-total")
  end
end
