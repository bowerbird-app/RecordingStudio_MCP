# frozen_string_literal: true

require "test_helper"

class EventsTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :published)

  def test_register_event_stores_a_host_event
    with_isolated_mcp_configuration do
      registration = RecordingStudioMcp.register_event("recording updated")

      assert_equal "recording updated", registration.name
      assert_equal :recording_updated, registration.trigger
      assert RecordingStudioMcp.event_registered?("recording updated")
      assert RecordingStudioMcp.events_registered?
    end
  end

  def test_register_event_block_sets_trigger_types_and_filter
    with_isolated_mcp_configuration do
      registration = RecordingStudioMcp.register_event("recording updated") do |event|
        event.on :recording_updated
        event.types "Page", "Document"
        event.if { |recording| recording.published == true }
      end

      page = FakeRecording.new(1, "Page", true)
      hidden = FakeRecording.new(2, "Page", false)
      other = FakeRecording.new(3, "Folder", true)

      assert registration.matches_recording?(page)
      refute registration.matches_recording?(hidden)
      refute registration.matches_recording?(other)
    end
  end

  def test_custom_event_has_no_built_in_trigger
    with_isolated_mcp_configuration do
      registration = RecordingStudioMcp.register_event("comment added")

      assert_nil registration.trigger
      refute registration.built_in_save?
    end
  end

  def test_if_requires_a_block
    with_isolated_mcp_configuration do
      assert_raises(ArgumentError) do
        RecordingStudioMcp.register_event("recording updated", &:if)
      end
    end
  end

  def test_notify_unregistered_raises
    with_isolated_mcp_configuration do
      assert_raises(ArgumentError) do
        RecordingStudioMcp.notify("comment added", recording: FakeRecording.new(1, "Page", true))
      end
    end
  end

  def test_unregistered_events_do_not_notify
    with_isolated_mcp_configuration do
      refute RecordingStudioMcp.event_registered?("recording updated")
      refute RecordingStudioMcp.events_registered?
    end
  end

  def test_event_catalog_is_enumerable
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      names = RecordingStudioMcp.configuration.event_catalog.map(&:name)

      assert_equal ["recording updated"], names
    end
  end

  def test_invalid_event_names_are_rejected
    with_isolated_mcp_configuration do
      assert_raises(ArgumentError) { RecordingStudioMcp.register_event("RecordingUpdated") }
      assert_raises(ArgumentError) { RecordingStudioMcp.register_event("") }
      assert_raises(ArgumentError) { RecordingStudioMcp.register_event("ok!") }
    end
  end

  def test_initialize_advertises_subscribe_only_when_an_event_is_registered
    with_isolated_mcp_configuration do
      hidden = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => { "protocolVersion" => "2025-06-18" } },
        access_grant: Struct.new(:api_client).new(nil)
      )
      assert_equal({}, hidden.body.dig(:result, :capabilities, :resources))

      RecordingStudioMcp.register_event("recording updated")
      shown = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 2, "method" => "initialize", "params" => { "protocolVersion" => "2025-06-18" } },
        access_grant: Struct.new(:api_client).new(nil)
      )
      assert_equal({ subscribe: true }, shown.body.dig(:result, :capabilities, :resources))
      assert_includes shown.body.dig(:result, :instructions), "Subscribe to a resource URI"
    end
  end
end
