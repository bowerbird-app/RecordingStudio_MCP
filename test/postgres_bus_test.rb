# frozen_string_literal: true

require "test_helper"

class PostgresBusTest < Minitest::Test
  def setup
    @previous_start_env = ENV.fetch(RecordingStudioMcp::PostgresBus::START_ENV, nil)
    RecordingStudioMcp::PostgresBus.stop!
  end

  def teardown
    RecordingStudioMcp::PostgresBus.stop!
    if @previous_start_env.nil?
      ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    else
      ENV[RecordingStudioMcp::PostgresBus::START_ENV] = @previous_start_env
    end
  end

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

  def test_start_allowed_is_false_under_rake_without_flag
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    rake_app = Object.new
    rake_app.define_singleton_method(:top_level_tasks) { ["db:migrate"] }

    RecordingStudioMcp::PostgresBus.stub(:rails_console?, false) do
      RecordingStudioMcp::PostgresBus.stub(:rails_runner?, false) do
        stub_rake_application(rake_app) do
          refute RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  end

  def test_start_allowed_is_false_under_console_without_flag
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)

    RecordingStudioMcp::PostgresBus.stub(:rails_console?, true) do
      RecordingStudioMcp::PostgresBus.stub(:rake_task?, false) do
        RecordingStudioMcp::PostgresBus.stub(:rails_runner?, false) do
          refute RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  end

  def test_start_allowed_is_true_when_env_flag_is_set
    ENV[RecordingStudioMcp::PostgresBus::START_ENV] = "1"

    RecordingStudioMcp::PostgresBus.stub(:rails_console?, true) do
      RecordingStudioMcp::PostgresBus.stub(:rake_task?, true) do
        RecordingStudioMcp::PostgresBus.stub(:rails_runner?, true) do
          assert RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  end

  def test_start_allowed_is_false_when_env_flag_disables
    ENV[RecordingStudioMcp::PostgresBus::START_ENV] = "0"

    RecordingStudioMcp::PostgresBus.stub(:rails_console?, false) do
      RecordingStudioMcp::PostgresBus.stub(:rake_task?, false) do
        RecordingStudioMcp::PostgresBus.stub(:rails_runner?, false) do
          refute RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  end

  def test_start_allowed_is_true_for_server_like_process
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)

    RecordingStudioMcp::PostgresBus.stub(:rails_console?, false) do
      RecordingStudioMcp::PostgresBus.stub(:rake_task?, false) do
        RecordingStudioMcp::PostgresBus.stub(:rails_runner?, false) do
          assert RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  end

  def test_start_is_a_noop_when_not_allowed
    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, false) do
        RecordingStudioMcp::PostgresBus.start!
        refute RecordingStudioMcp::PostgresBus.listening?
      end
    end
  end

  def test_start_listens_then_stop_releases_the_connection_once
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
    listen_connection.define_singleton_method(:active?) { true }

    pool = Object.new
    checked_in = []
    pool.define_singleton_method(:checkout) { listen_connection }
    pool.define_singleton_method(:checkin) { |connection| checked_in << connection }

    RecordingStudioMcp::Notifier.stub(:deliver_local, ->(**kwargs) { payloads << kwargs }) do
      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
          RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
            ActiveRecord::Base.stub(:connection_pool, pool) do
              RecordingStudioMcp::PostgresBus.start!
              sleep 0.15
              RecordingStudioMcp::PostgresBus.stop!
            end
          end
        end
      end
    end

    assert_equal [{ event_name: "recording updated", recording_id: "9" }], payloads
    assert_equal [listen_connection], checked_in
    refute RecordingStudioMcp::PostgresBus.listening?
  end

  def test_release_is_a_noop_after_connection_already_closed
    raw = Object.new
    raw.define_singleton_method(:finished?) { true }
    connection = Object.new
    connection.define_singleton_method(:raw_connection) { raw }
    connection.define_singleton_method(:active?) { raise IOError, "stream closed in another thread" }
    executed = []
    connection.define_singleton_method(:execute) { |sql| executed << sql }

    checked_in = []
    pool = Object.new
    pool.define_singleton_method(:checkin) { |conn| checked_in << conn }

    RecordingStudioMcp::PostgresBus.instance_variable_set(:@listen_connection, connection)
    ActiveRecord::Base.stub(:connection_pool, pool) do
      RecordingStudioMcp::PostgresBus.send(:release_listen_connection)
      RecordingStudioMcp::PostgresBus.send(:release_listen_connection)
    end

    assert_empty executed
    assert_equal [connection], checked_in
    assert_nil RecordingStudioMcp::PostgresBus.instance_variable_get(:@listen_connection)
  end

  def test_wait_for_notify_stream_closed_does_not_leak_ioerror
    raw = Object.new
    raw.define_singleton_method(:wait_for_notify) do |*_args|
      raise IOError, "stream closed in another thread"
    end
    listen_connection = Object.new
    listen_connection.define_singleton_method(:execute) { |_| }
    listen_connection.define_singleton_method(:raw_connection) { raw }
    listen_connection.define_singleton_method(:active?) { false }

    pool = Object.new
    checked_in = []
    pool.define_singleton_method(:checkout) { listen_connection }
    pool.define_singleton_method(:checkin) { |connection| checked_in << connection }

    thread_error = nil
    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
          ActiveRecord::Base.stub(:connection_pool, pool) do
            RecordingStudioMcp::PostgresBus.start!
            thread = RecordingStudioMcp::PostgresBus.instance_variable_get(:@thread)
            if thread
              begin
                thread.join(2)
                thread.value
              rescue IOError => e
                thread_error = e
              end
            end
            RecordingStudioMcp::PostgresBus.stop!
          end
        end
      end
    end

    assert_nil thread_error
    refute RecordingStudioMcp::PostgresBus.listening?
    assert_includes checked_in, listen_connection
  end

  def stub_rake_application(rake_app)
    rake_defined = Object.const_defined?(:Rake)
    original = rake_defined ? Rake : nil
    fake = Module.new
    fake.define_singleton_method(:application) { rake_app }
    fake.define_singleton_method(:respond_to?) { |method, *| method == :application || super(method) }

    Object.send(:remove_const, :Rake) if rake_defined
    Object.const_set(:Rake, fake)
    yield
  ensure
    Object.send(:remove_const, :Rake) if Object.const_defined?(:Rake)
    Object.const_set(:Rake, original) if rake_defined && original
  end
end
