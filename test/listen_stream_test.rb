# frozen_string_literal: true

require "test_helper"

class ListenStreamTest < Minitest::Test
  FakeSender = Struct.new(:payloads, keyword_init: true) do
    def initialize(payloads: [])
      super
    end

    def write_json(payload)
      payloads << payload
    end

    def write_comment(*); end

    def disconnected?
      false
    end

    def closed?
      false
    end
  end

  def test_modern_listen_acknowledges_then_delivers_tagged_updates
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = Object.new
      connection = RecordingStudioMcp::Connections.open(
        protocol_version: "2026-07-28",
        access_grant: grant,
        subscription_id: 4
      )
      connection.subscribe("recording://11")
      sender = FakeSender.new
      connection.attach_sender(sender)

      ack = connection.acknowledged_payload
      assert_equal "notifications/subscriptions/acknowledged", ack[:method]
      assert_equal 4, ack.dig(:params, :_meta, RecordingStudioMcp::Connection::SUBSCRIPTION_ID_META)
      assert_equal ["recording://11"], ack.dig(:params, :notifications, :resourceSubscriptions)

      connection.enqueue_updated("recording://11")
      update_payload = connection.shift_pending(timeout: 0)
      assert connection.write_payload(sender, update_payload)
      update = sender.payloads.last
      assert_equal "notifications/resources/updated", update[:method]
      assert_equal "recording://11", update.dig(:params, :uri)
      assert_equal 4, update.dig(:params, :_meta, RecordingStudioMcp::Connection::SUBSCRIPTION_ID_META)
    end
  end

  def test_recording_card_falls_back_when_labels_fail
    recordable = Object.new
    recording = Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)
                      .new(3, "Page", recordable, nil, 1)
    RecordingStudio.stub(:recordable_name, ->(*) { raise "nope" }) do
      card = RecordingStudioMcp::RecordingCard.new(recording)
      assert_equal "Page", card.name
    end

    titled = Struct.new(:title).new("Fallback")
    named = RecordingStudioMcp::RecordingCard.new(
      Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)
        .new(4, "Page", titled, nil, 1)
    )
    RecordingStudio.stub(:recordable_name, ->(*) {}) do
      assert_equal "Fallback", named.title
    end
  end

  def test_notify_marks_finished_when_the_writer_disconnects
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: Object.new
    )
    sender = Object.new
    sender.define_singleton_method(:write_json) { |_| raise IOError, "broken" }
    sender.define_singleton_method(:disconnected?) { false }
    sender.define_singleton_method(:closed?) { false }
    connection.attach_sender(sender)
    connection.subscribe("recording://3")

    connection.enqueue_updated("recording://3")
    payload = connection.shift_pending(timeout: 0)
    refute connection.write_payload(sender, payload)
    assert connection.finished?
  end

  def test_legacy_updates_omit_subscription_id
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: Object.new
    )
    sender = FakeSender.new
    connection.attach_sender(sender)
    connection.subscribe("recording://3")
    connection.enqueue_updated("recording://3")
    connection.write_payload(sender, connection.shift_pending(timeout: 0))

    refute sender.payloads.first[:params].key?(:_meta)
  end

  def test_listen_stream_acknowledges_then_stops_on_finish
    grant = Object.new
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2026-07-28",
      access_grant: grant,
      subscription_id: 9
    )
    connection.subscribe("recording://2")
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 9,
      protocol_version: "2026-07-28",
      access_grant: grant
    )
    io = StringIO.new
    writer = RecordingStudioMcp::SseWriter.new(io)
    stream = RecordingStudioMcp::ListenStream.new(
      connection: connection,
      request_context: context,
      write_ack: true
    )

    thread = Thread.new { stream.perform(writer) }
    sleep 0.05
    connection.enqueue_updated("recording://2")
    sleep 0.05
    connection.finish!
    thread.join(2)

    frames = io.string
    assert_includes frames, "notifications/subscriptions/acknowledged"
    assert_includes frames, '"resultType":"complete"'
    assert_includes frames, "io.modelcontextprotocol/subscriptionId"
    assert connection.finished?
    assert_nil RecordingStudioMcp::Connections.fetch(connection.id)
  end

  def test_write_timeout_drops_a_stalled_subscriber
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: Object.new
    )
    sender = Object.new
    sender.define_singleton_method(:write_json) { |_| sleep 2 }
    connection.subscribe("recording://3")
    connection.enqueue_updated("recording://3")

    refute connection.write_payload(sender, connection.shift_pending(timeout: 0))
    assert connection.finished?
  end

  def test_enqueue_stops_when_finished
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: Object.new
    )
    connection.subscribe("recording://3")
    connection.finish!

    refute connection.enqueue_updated("recording://3")
    refute connection.pending?
    connection.wait(timeout: 0.01)
    assert_equal [connection], RecordingStudioMcp::Connections.to_a
  end

  def test_listen_completion_swallows_a_dead_writer
    grant = Object.new
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2026-07-28",
      access_grant: grant,
      subscription_id: 3
    )
    connection.finish!
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 3,
      protocol_version: "2026-07-28",
      access_grant: grant
    )
    writer = Object.new
    writes = 0
    writer.define_singleton_method(:write_json) do |_|
      writes += 1
      raise IOError, "gone" if writes > 1
    end
    writer.define_singleton_method(:write_comment) {}
    writer.define_singleton_method(:disconnected?) { false }
    writer.define_singleton_method(:closed?) { false }
    stream = RecordingStudioMcp::ListenStream.new(
      connection: connection,
      request_context: context,
      write_ack: true
    )

    stream.perform(writer)
    assert connection.finished?
  end

  def test_disconnect_drops_the_in_memory_connection
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: Object.new
    )
    id = connection.id
    RecordingStudioMcp::Connections.drop(id)

    assert connection.finished?
    assert_nil RecordingStudioMcp::Connections.fetch(id)
  end
end
