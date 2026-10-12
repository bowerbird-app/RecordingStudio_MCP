# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class PostgresBusTest < Minitest::Test
  def setup
    @previous_start_env = ENV.fetch(RecordingStudioMcp::PostgresBus::START_ENV, nil)
    RecordingStudioMcp::PostgresBus.stop!
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, nil)
  end

  def teardown
    RecordingStudioMcp::PostgresBus.stop!
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, nil)
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

  def test_start_allowed_is_false_when_runner_command_is_defined
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)

    RecordingStudioMcp::PostgresBus.stub(:rails_console?, false) do
      RecordingStudioMcp::PostgresBus.stub(:rake_task?, false) do
        RecordingStudioMcp::PostgresBus.stub(:rails_runner?, true) do
          refute RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  end

  def test_rails_runner_detects_command_constant_not_argv
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    previous_argv = ARGV.dup
    ARGV.replace([])

    with_runner_command_defined do
      RecordingStudioMcp::PostgresBus.stub(:rails_console?, false) do
        RecordingStudioMcp::PostgresBus.stub(:rake_task?, false) do
          assert RecordingStudioMcp::PostgresBus.send(:rails_runner?)
          refute RecordingStudioMcp::PostgresBus.start_allowed?
        end
      end
    end
  ensure
    ARGV.replace(previous_argv)
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

  def test_wait_for_notify_stream_closed_logs_and_reconnects
    log_io = StringIO.new
    logger = Logger.new(log_io)
    opens = 0
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
    pool.define_singleton_method(:checkout) do
      opens += 1
      listen_connection
    end
    pool.define_singleton_method(:checkin) { |connection| checked_in << connection }

    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
          RecordingStudioMcp::PostgresBus.stub(:interruptible_sleep, nil) do
            ActiveRecord::Base.stub(:connection_pool, pool) do
              Rails.stub(:logger, logger) do
                RecordingStudioMcp::PostgresBus.start!
                thread = RecordingStudioMcp::PostgresBus.instance_variable_get(:@thread)
                thread&.join(2)
                RecordingStudioMcp::PostgresBus.stop!
              end
            end
          end
        end
      end
    end

    log = log_io.string
    assert_includes log, "LISTEN wait failed: IOError: stream closed in another thread"
    assert_includes log, "LISTEN reconnecting"
    assert_operator opens, :>, 1
    refute RecordingStudioMcp::PostgresBus.listening?
    assert_includes checked_in, listen_connection
  end

  def test_stop_does_not_release_connection_when_join_times_out
    connection = Object.new
    connection.define_singleton_method(:raw_connection) { nil }
    connection.define_singleton_method(:active?) { true }
    connection.define_singleton_method(:execute) { |_| flunk "should not UNLISTEN while thread alive" }

    checked_in = []
    pool = Object.new
    pool.define_singleton_method(:checkin) { |conn| checked_in << conn }

    stuck = Object.new
    stuck.define_singleton_method(:join) { |*_args| nil }
    stuck.define_singleton_method(:alive?) { true }

    log_io = StringIO.new
    logger = Logger.new(log_io)

    RecordingStudioMcp::PostgresBus.instance_variable_set(:@running, true)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@thread, stuck)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@listen_connection, connection)

    RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
      ActiveRecord::Base.stub(:connection_pool, pool) do
        Rails.stub(:logger, logger) do
          RecordingStudioMcp::PostgresBus.stop!
        end
      end
    end

    assert_empty checked_in
    assert_same connection, RecordingStudioMcp::PostgresBus.instance_variable_get(:@listen_connection)
    assert_includes log_io.string, "did not stop within"
  ensure
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@listen_connection, nil)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@thread, nil)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@running, false)
  end

  def test_shutdown_hook_skips_forked_child_pid
    stop_calls = 0
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, Process.pid + 99)
    RecordingStudioMcp::PostgresBus.stub(:stop!, -> { stop_calls += 1 }) do
      RecordingStudioMcp::PostgresBus.send(:shutdown_if_owner!)
    end

    assert_equal 0, stop_calls
  end

  def test_shutdown_hook_runs_for_owner_pid
    stop_calls = 0
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, Process.pid)
    RecordingStudioMcp::PostgresBus.stub(:stop!, -> { stop_calls += 1 }) do
      RecordingStudioMcp::PostgresBus.send(:shutdown_if_owner!)
    end

    assert_equal 1, stop_calls
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

  def with_runner_command_defined
    rails_defined = Object.const_defined?(:Rails)
    command_defined = rails_defined && Rails.const_defined?(:Command)
    runner_defined = command_defined && Rails::Command.const_defined?(:RunnerCommand)

    return yield if runner_defined

    Object.const_set(:Rails, Module.new) unless rails_defined
    Rails.const_set(:Command, Module.new) unless Rails.const_defined?(:Command)
    Rails::Command.const_set(:RunnerCommand, Class.new)

    yield
  ensure
    if !runner_defined && Rails.const_defined?(:Command) && Rails::Command.const_defined?(:RunnerCommand)
      Rails::Command.send(:remove_const, :RunnerCommand)
    end
  end
end
