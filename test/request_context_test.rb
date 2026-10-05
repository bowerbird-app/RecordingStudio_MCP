# frozen_string_literal: true

require "test_helper"

class RequestContextTest < Minitest::Test
  FakeSender = Struct.new(:payloads, :disconnected, keyword_init: true) do
    def initialize(payloads: [], disconnected: false)
      super
    end

    def write_json(payload)
      payloads << payload
    end

    def disconnected?
      disconnected
    end
  end

  def test_progress_echoes_token_without_jsonrpc_id
    sender = FakeSender.new
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 9,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      progress_token: "tok-1",
      sender: sender
    )

    context.progress(current: 1, total: 4, message: "Working")
    payload = sender.payloads.first

    refute payload.key?(:id)
    assert_equal "notifications/progress", payload[:method]
    assert_equal "tok-1", payload.dig(:params, :progressToken)
    assert_equal 1, payload.dig(:params, :progress)
    assert_equal 4, payload.dig(:params, :total)
    assert_equal "Working", payload.dig(:params, :message)
    refute_equal 9, payload[:id]
  end

  def test_progress_is_noop_without_token_after_complete_or_disconnect
    sender = FakeSender.new
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      progress_token: nil,
      sender: sender
    )
    context.progress(current: 1, total: 2, message: "nope")

    with_token = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      progress_token: 12,
      sender: sender
    )
    with_token.complete!
    with_token.progress(current: 1)
    with_token.disconnect!
    disconnected = RecordingStudioMcp::RequestContext.new(
      request_id: 2,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      progress_token: "x",
      sender: sender
    )
    disconnected.disconnect!
    disconnected.progress(current: 1)

    assert_empty sender.payloads
  end

  def test_progress_must_increase_and_omits_message_on_older_revision
    sender = FakeSender.new
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-03-26",
      access_grant: Object.new,
      progress_token: "t",
      sender: sender
    )

    context.progress(current: 2, total: 5, message: "hidden")
    context.progress(current: 2, total: 5)
    context.progress(current: 1, total: 5)
    context.progress(current: 3, total: 2)
    context.progress(current: 4, total: 5)

    assert_equal 2, sender.payloads.length
    refute sender.payloads.first[:params].key?(:message)
    assert_equal 2, sender.payloads.first.dig(:params, :progress)
    assert_equal 4, sender.payloads.last.dig(:params, :progress)
  end

  def test_progress_reporter_is_self_only_when_token_and_sender_exist
    sender = FakeSender.new
    streaming = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      progress_token: "t",
      sender: sender
    )
    json_only = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      progress_token: "t"
    )
    no_token = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-06-18",
      access_grant: Object.new,
      sender: sender
    )

    assert_same streaming, streaming.progress_reporter
    assert_equal false, streaming.cancelled?
    streaming.disconnect!
    assert_equal true, streaming.cancelled?
    assert_nil json_only.progress_reporter
    assert_nil no_token.progress_reporter
  end

  def test_contexts_do_not_share_notifications
    first_sender = FakeSender.new
    second_sender = FakeSender.new
    first = RecordingStudioMcp::RequestContext.new(
      request_id: 1,
      protocol_version: "2025-06-18",
      access_grant: :a,
      progress_token: "a",
      sender: first_sender
    )
    second = RecordingStudioMcp::RequestContext.new(
      request_id: 2,
      protocol_version: "2025-06-18",
      access_grant: :b,
      progress_token: "b",
      sender: second_sender
    )

    first.progress(current: 1)
    second.progress(current: 9)

    assert_equal(["a"], first_sender.payloads.map { |payload| payload.dig(:params, :progressToken) })
    assert_equal(["b"], second_sender.payloads.map { |payload| payload.dig(:params, :progressToken) })
  end
end
