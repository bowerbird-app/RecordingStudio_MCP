# frozen_string_literal: true

require "test_helper"

class StreamDecisionTest < Minitest::Test
  def test_streams_only_for_tools_call_with_token_and_sse_accept
    params = { "name" => "demo_progress", "_meta" => { "progressToken" => "p1" } }

    assert RecordingStudioMcp::StreamDecision.stream?(
      method_name: "tools/call",
      params: params,
      accept_header: "application/json, text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.stream?(
      method_name: "tools/list",
      params: params,
      accept_header: "application/json, text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.stream?(
      method_name: "ping",
      params: params,
      accept_header: "text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.stream?(
      method_name: "tools/call",
      params: { "name" => "list" },
      accept_header: "application/json, text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.stream?(
      method_name: "tools/call",
      params: params,
      accept_header: "application/json"
    )
    refute RecordingStudioMcp::StreamDecision.stream?(
      method_name: "tools/call",
      params: params,
      accept_header: "*/*"
    )
  end

  def test_invalid_tokens_are_ignored
    [
      nil,
      { "progressToken" => nil },
      { "progressToken" => true },
      { "progressToken" => 1.5 },
      { "progressToken" => { "n" => 1 } },
      { "progressToken" => ["x"] }
    ].each do |meta|
      params = { "name" => "list", "_meta" => meta }
      assert_nil RecordingStudioMcp::StreamDecision.progress_token(params)
    end

    assert_equal "abc", RecordingStudioMcp::StreamDecision.progress_token(
      "_meta" => { "progressToken" => "abc" }
    )
    assert_equal 7, RecordingStudioMcp::StreamDecision.progress_token(
      "_meta" => { "progressToken" => 7 }
    )
  end

  def test_legacy_get_listen_is_sse_on_older_revisions
    assert RecordingStudioMcp::StreamDecision.legacy_get_listen?(
      protocol_version: "2025-06-18",
      accept_header: "text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.legacy_get_listen?(
      protocol_version: "2026-07-28",
      accept_header: "text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.legacy_get_listen?(
      protocol_version: "2025-06-18",
      accept_header: "application/json"
    )
  end

  def test_modern_listen_is_subscriptions_listen
    assert RecordingStudioMcp::StreamDecision.listen?(
      method_name: "subscriptions/listen",
      protocol_version: "2026-07-28",
      accept_header: "application/json, text/event-stream"
    )
    refute RecordingStudioMcp::StreamDecision.listen?(
      method_name: "subscriptions/listen",
      protocol_version: "2025-06-18",
      accept_header: "text/event-stream"
    )
  end
end
