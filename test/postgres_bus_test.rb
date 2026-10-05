# frozen_string_literal: true

require "test_helper"

class PostgresBusTest < Minitest::Test
  def test_enabled_is_false_when_not_connected
    ActiveRecord::Base.stub(:connected?, false) do
      refute RecordingStudioMcp::PostgresBus.enabled?
    end
  end

  def test_enabled_is_false_when_the_adapter_check_raises
    ActiveRecord::Base.stub(:connected?, true) do
      ActiveRecord::Base.stub(:connection, -> { raise "gone" }) do
        refute RecordingStudioMcp::PostgresBus.enabled?
      end
    end
  end

  def test_enabled_is_false_when_active_record_is_missing
    RecordingStudioMcp::PostgresBus.stub(:enabled?, false) do
      refute RecordingStudioMcp::PostgresBus.enabled?
    end
  end

  def test_publish_notifies_the_channel
    executed = []
    connection = Object.new
    connection.define_singleton_method(:quote) { |value| "'#{value}'" }
    connection.define_singleton_method(:execute) { |sql| executed << sql }

    ActiveRecord::Base.stub(:connection, connection) do
      RecordingStudioMcp::PostgresBus.publish(event_name: "recording updated", recording_id: 9)
    end

    assert_includes executed.first, "NOTIFY #{RecordingStudioMcp::PostgresBus::CHANNEL}"
    assert_includes executed.first, "recording updated"
  end

  def test_start_listens_then_stop_releases_the_connection
    payloads = []
    raw = Object.new
    calls = 0
    raw.define_singleton_method(:wait_for_notify) do |*_args, &block|
      calls += 1
      if calls == 1
        block&.call("recording_studio_mcp_events", 1, { "event" => "recording updated", "id" => "9" }.to_json)
      else
        sleep 0.05
      end
    end
    listen_connection = Object.new
    listen_connection.define_singleton_method(:execute) { |_| }
    listen_connection.define_singleton_method(:raw_connection) { raw }

    pool = Object.new
    checked_in = []
    pool.define_singleton_method(:checkout) { listen_connection }
    pool.define_singleton_method(:checkin) { |connection| checked_in << connection }

    RecordingStudioMcp::Notifier.stub(:deliver_local, ->(**kwargs) { payloads << kwargs }) do
      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        ActiveRecord::Base.stub(:connection_pool, pool) do
          RecordingStudioMcp::PostgresBus.start!
          sleep 0.15
          RecordingStudioMcp::PostgresBus.stop!
        end
      end
    end

    assert_equal [{ event_name: "recording updated", recording_id: "9" }], payloads
    assert_includes checked_in, listen_connection
    refute RecordingStudioMcp::PostgresBus.listening?
  end
end
