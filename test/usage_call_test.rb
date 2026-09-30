# frozen_string_literal: true

require "test_helper"

class UsageCallTest < Minitest::Test
  def setup
    @recorded = []
    RecordingStudioMcp::UsageRecorder.sink = ->(payload) { @recorded << payload }
  end

  def teardown
    RecordingStudioMcp::UsageRecorder.sink = nil
  end

  def test_tools_call_keeps_the_tool_name_and_drops_the_arguments
    payload = record(
      request_payload: {
        "method" => "tools/call",
        "params" => { "name" => "list", "arguments" => { "title" => "Secret title" } }
      },
      response_body: { "result" => { "isError" => false } },
      status: 200,
      duration_ms: 12,
      rate_limited: false,
      api_client_id: "client-1"
    )

    assert_equal(
      {
        method_name: "tools/call",
        subject_name: "list",
        status_code: 200,
        duration_ms: 12,
        rate_limited: false,
        failed: false,
        api_client_id: "client-1"
      },
      payload
    )
    refute_includes @recorded.first.values.map(&:to_s).join, "Secret title"
  end

  def test_skill_uri_is_stored_as_the_skill_name
    payload = attributes(
      request_payload: { "method" => "skills/get", "params" => { "uri" => "skill://desk-notes/SKILL.md" } },
      response_body: { "result" => {} },
      status: :ok,
      duration_ms: 4,
      rate_limited: false,
      api_client_id: nil
    )

    assert_equal "desk-notes", payload.fetch(:subject_name)
    assert_equal 200, payload.fetch(:status_code)
  end

  def test_tool_error_and_rate_limit_count_as_failed
    tool_error = attributes(
      request_payload: { "method" => "tools/call", "params" => { "name" => "missing" } },
      response_body: { "result" => { "isError" => true } },
      status: 200,
      duration_ms: 3,
      rate_limited: false,
      api_client_id: nil
    )
    limited = attributes(
      request_payload: { "method" => "tools/list" },
      response_body: { "error" => { "code" => "rate_limit_exceeded" } },
      status: 429,
      duration_ms: 1,
      rate_limited: true,
      api_client_id: nil
    )

    assert tool_error.fetch(:failed)
    assert_equal "missing", tool_error.fetch(:subject_name)
    assert limited.fetch(:failed)
    assert limited.fetch(:rate_limited)
    assert_equal "", limited.fetch(:subject_name)
  end

  def test_a_failed_write_does_not_raise
    warnings = []
    logger = Object.new
    logger.define_singleton_method(:warn) { |message| warnings << message }
    RecordingStudioMcp::UsageRecorder.sink = ->(_payload) { raise "disk full" }

    result = Rails.stub(:logger, logger) do
      record(
        request_payload: { "method" => "ping" },
        response_body: {},
        status: 200,
        duration_ms: 1,
        rate_limited: false,
        api_client_id: nil
      )
    end

    assert_nil result
    assert_match(/disk full/, warnings.join)
  end

  def test_blank_method_and_a_long_subject_are_bounded
    payload = attributes(
      request_payload: { "method" => " " },
      response_body: {},
      status: 200,
      duration_ms: 1,
      rate_limited: false,
      api_client_id: nil
    )

    assert_equal "unknown", payload.fetch(:method_name)
    assert_equal "", payload.fetch(:subject_name)
  end

  def test_a_resource_uri_that_is_not_a_skill_is_stored_as_given
    uri = "https://example.test/notes"
    payload = attributes(
      request_payload: { "method" => "resources/read", "params" => { "uri" => uri } },
      response_body: { "result" => {} },
      status: 200,
      duration_ms: 1,
      rate_limited: false,
      api_client_id: nil
    )

    assert_equal uri, payload.fetch(:subject_name)
  end

  def test_a_tool_name_is_truncated
    payload = attributes(
      request_payload: { "method" => "tools/call", "params" => { "name" => "n" * 300 } },
      response_body: {},
      status: 200,
      duration_ms: 1,
      rate_limited: false,
      api_client_id: nil
    )

    assert_equal 255, payload.fetch(:subject_name).length
  end

  private

  def attributes(**keywords)
    RecordingStudioMcp::UsageCall.new(**keywords).attributes
  end

  def record(**keywords)
    RecordingStudioMcp::UsageRecorder.record!(RecordingStudioMcp::UsageCall.new(**keywords))
  end
end
