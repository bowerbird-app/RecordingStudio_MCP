# frozen_string_literal: true

require "test_helper"

class NotifierTest < Minitest::Test
  FakeSender = Struct.new(:payloads, keyword_init: true) do
    def initialize(payloads: [])
      super
    end

    def write_json(payload)
      payloads << payload
    end

    def disconnected?
      false
    end

    def closed?
      false
    end
  end

  FakeGrant = Struct.new(:allowed_ids) do
    def accessible_recordings
      ids = allowed_ids
      Object.new.tap do |scope|
        scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
        scope.define_singleton_method(:find_by) { |id:| ids.include?(id) ? Object.new : nil }
      end
    end
  end

  FakeRecording = Struct.new(:id)
  FakeEvent = Struct.new(:recording)

  def test_registered_event_notifies_only_subscribed_connections
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      watching = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      ignored = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      sender = FakeSender.new
      other = FakeSender.new
      watching.attach_sender(sender)
      ignored.attach_sender(other)
      watching.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7)))

      assert_equal 1, sender.payloads.length
      assert_equal "notifications/resources/updated", sender.payloads.first[:method]
      assert_equal "recording://7", sender.payloads.first.dig(:params, :uri)
      assert_empty other.payloads
    end
  end

  def test_unregistered_events_never_notify
    with_isolated_mcp_configuration do
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      sender = FakeSender.new
      connection.attach_sender(sender)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7)))

      assert_empty sender.payloads
    end
  end

  def test_lost_access_does_not_notify
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      sender = FakeSender.new
      connection.attach_sender(sender)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7)))

      assert_empty sender.payloads
    end
  end
end
