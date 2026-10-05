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

      connection.notify_updated("recording://11")
      update = sender.payloads.last
      assert_equal "notifications/resources/updated", update[:method]
      assert_equal "recording://11", update.dig(:params, :uri)
      assert_equal 4, update.dig(:params, :_meta, RecordingStudioMcp::Connection::SUBSCRIPTION_ID_META)
    end
  end

  def test_legacy_updates_omit_subscription_id
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: Object.new
    )
    sender = FakeSender.new
    connection.attach_sender(sender)
    connection.subscribe("recording://3")
    connection.notify_updated("recording://3")

    refute sender.payloads.first[:params].key?(:_meta)
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
