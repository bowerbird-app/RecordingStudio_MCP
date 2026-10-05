# frozen_string_literal: true

require "test_helper"

class NotifierTest < Minitest::Test
  FakeGrant = Struct.new(:allowed_ids) do
    def accessible_recordings
      ids = allowed_ids
      Object.new.tap do |scope|
        scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
        scope.define_singleton_method(:find_by) { |id:| ids.include?(id) ? Object.new : nil }
      end
    end
  end

  FakeRecording = Struct.new(:id, :recordable_type, :published)
  FakeEvent = Struct.new(:recording)

  def test_registered_event_enqueues_only_for_subscribed_connections
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      watching = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      ignored = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      watching.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      payload = watching.shift_pending(timeout: 0)
      assert_equal "notifications/resources/updated", payload[:method]
      assert_equal "recording://7", payload.dig(:params, :uri)
      assert_nil ignored.shift_pending(timeout: 0)
    end
  end

  def test_save_returns_while_a_subscriber_queue_is_not_drained
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :<, 0.2
      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_full_queue_drops_the_slow_subscriber
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Connection::QUEUE_LIMIT.times do
        assert connection.enqueue_updated("recording://7")
      end
      refute connection.enqueue_updated("recording://7")
      assert connection.finished?
    end
  end

  def test_types_and_if_filters_skip_notify
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated") do |event|
        event.on :recording_updated
        event.types "Page"
        event.if { |recording| recording.published == true }
      end
      grant = FakeGrant.new([7, 8, 9])
      watching = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      watching.subscribe("recording://7")
      watching.subscribe("recording://8")
      watching.subscribe("recording://9")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", false)))
      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(8, "Folder", true)))
      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(9, "Page", true)))

      uris = []
      while (payload = watching.shift_pending(timeout: 0))
        uris << payload.dig(:params, :uri)
      end
      assert_equal ["recording://9"], uris
    end
  end

  def test_custom_notify_enqueues_and_unregistered_raises
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("comment added")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp.notify("comment added", recording: FakeRecording.new(7, "Page", true))
      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)

      assert_raises(ArgumentError) do
        RecordingStudioMcp.notify("never registered", recording: FakeRecording.new(7, "Page", true))
      end
      assert_raises(ArgumentError) do
        RecordingStudioMcp.notify("comment added", recording: nil)
      end
    end
  end

  def test_unregistered_events_never_notify
    with_isolated_mcp_configuration do
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_nil connection.shift_pending(timeout: 0)
    end
  end

  def test_deliver_local_loads_a_recording_by_id
    skip unless defined?(RecordingStudio::Recording)

    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")
      found = FakeRecording.new(7, "Page", true)
      RecordingStudio::Recording.stub(:find_by, found) do
        RecordingStudioMcp::Notifier.deliver_local(event_name: "recording updated", recording_id: 7)
      end

      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_event_without_a_recording_is_ignored
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      event = Object.new
      event.define_singleton_method(:recording) { nil }
      event.define_singleton_method(:recording_id) { 7 }

      RecordingStudioMcp::Notifier.recording_saved(event)
    end
  end

  def test_a_broken_connection_is_dropped
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")
      connection.define_singleton_method(:enqueue_updated) { |_| raise "queue down" }

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert connection.finished?
    end
  end

  def test_lost_access_does_not_notify
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_nil connection.shift_pending(timeout: 0)
    end
  end
end
