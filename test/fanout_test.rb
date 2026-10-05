# frozen_string_literal: true

require "test_helper"

class FanoutTest < Minitest::Test
  FakeGrant = Struct.new(:allowed_ids) do
    def accessible_recordings
      ids = allowed_ids
      Object.new.tap do |scope|
        scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
        scope.define_singleton_method(:find_by) { |id:| ids.include?(id) ? Object.new : nil }
      end
    end
  end

  FakeRecording = Struct.new(:id, :recordable_type)

  def test_non_postgres_delivers_in_process
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([4])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://4")

      RecordingStudioMcp::Notifier.stub(:find_recording, FakeRecording.new(4, "Page")) do
        RecordingStudioMcp::PostgresBus.stub(:enabled?, false) do
          RecordingStudioMcp::Fanout.publish(event_name: "recording updated", recording_id: 4)
        end
      end

      assert_equal "recording://4", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_postgres_path_notifies_without_local_enqueue
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      published = []
      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:publish, lambda { |event_name:, recording_id:|
          published << [event_name, recording_id]
        }) do
          RecordingStudioMcp::Fanout.publish(event_name: "recording updated", recording_id: 11)
        end
      end

      assert_equal [["recording updated", 11]], published
    end
  end

  def test_listen_payload_rechecks_access_and_local_subscribers
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([5])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://5")

      RecordingStudioMcp::Notifier.stub(:find_recording, FakeRecording.new(5, "Page")) do
        RecordingStudioMcp::PostgresBus.handle_payload({ "event" => "recording updated", "id" => "5" }.to_json)
      end

      assert_equal "recording://5", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end
end
