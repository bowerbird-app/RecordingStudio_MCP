# frozen_string_literal: true

require "test_helper"

class EventsTest < Minitest::Test
  def test_register_event_stores_a_host_event
    with_isolated_mcp_configuration do
      registration = RecordingStudioMcp.register_event("recording updated")

      assert_equal "recording updated", registration.name
      assert RecordingStudioMcp.event_registered?("recording updated")
      assert RecordingStudioMcp.events_registered?
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
