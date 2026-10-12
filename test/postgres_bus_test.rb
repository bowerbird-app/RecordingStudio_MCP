# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class PostgresBusTest < Minitest::Test
  def setup
    @previous_start_env = ENV.fetch(RecordingStudioMcp::PostgresBus::START_ENV, nil)
    RecordingStudioMcp::PostgresBus.stop!
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, nil)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@last_warn_at, nil)
  end

  def teardown
    RecordingStudioMcp::PostgresBus.stop!
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, nil)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@last_warn_at, nil)
    if @previous_start_env.nil?
      ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    else
      ENV[RecordingStudioMcp::PostgresBus::START_ENV] = @previous_start_env
    end
  end

  def test_enabled_does_not_require_an_open_connection
    db_config = Object.new
    db_config.define_singleton_method(:adapter) { "postgresql" }

    ActiveRecord::Base.stub(:connected?, false) do
      ActiveRecord::Base.stub(:connection_db_config, db_config) do
        assert RecordingStudioMcp::PostgresBus.enabled?
      end
    end
  end

  def test_enabled_is_false_when_adapter_is_not_postgres
    db_config = Object.new
    db_config.define_singleton_method(:adapter) { "sqlite3" }

    ActiveRecord::Base.stub(:connection_db_config, db_config) do
      refute RecordingStudioMcp::PostgresBus.enabled?
    end
  end

  def test_enabled_is_false_when_the_adapter_check_raises
    ActiveRecord::Base.stub(:connection_db_config, -> { raise "gone" }) do
      refute RecordingStudioMcp::PostgresBus.enabled?
    end
  end

  def test_enabled_is_false_when_active_record_is_missing
    RecordingStudioMcp::PostgresBus.stub(:enabled?, false) do
      refute RecordingStudioMcp::PostgresBus.enabled?
    end
  end

  def test_start_abandons_inherited_state_after_fork
    parent_connection = Object.new
    # After fork only the forking thread survives; simulate a dead inherited thread.
    stale_thread = Thread.new { sleep 60 }
    stale_thread.kill
    stale_thread.join(1)

    RecordingStudioMcp::PostgresBus.instance_variable_set(:@owner_pid, Process.pid + 99)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@listen_connection, parent_connection)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@thread, stale_thread)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@running, true)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@shutdown_hook_registered, true)

    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
          RecordingStudioMcp::PostgresBus.stub(:listen_loop, nil) do
            RecordingStudioMcp::PostgresBus.start!
            assert_equal Process.pid, RecordingStudioMcp::PostgresBus.instance_variable_get(:@owner_pid)
            assert_nil RecordingStudioMcp::PostgresBus.instance_variable_get(:@listen_connection)
            assert RecordingStudioMcp::PostgresBus.listening?
            RecordingStudioMcp::PostgresBus.stop!
          end
        end
      end
    end
  ensure
    thread = RecordingStudioMcp::PostgresBus.instance_variable_get(:@thread)
    thread&.kill
    thread&.join(1)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@thread, nil)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@listen_connection, nil)
    RecordingStudioMcp::PostgresBus.instance_variable_set(:@running, false)
  end

  def test_announce_listening_logs_once
    io = StringIO.new
    logger = Logger.new(io)

    RecordingStudioMcp::PostgresBus.instance_variable_set(:@listen_announced, false)
    Rails.stub(:logger, logger) do
      RecordingStudioMcp::PostgresBus.send(:announce_listening!)
      RecordingStudioMcp::PostgresBus.send(:announce_listening!)
    end

    lines = io.string.lines.select { |line| line.include?("listening on") }
    assert_equal 1, lines.size
    assert_includes lines.first, RecordingStudioMcp::PostgresBus::CHANNEL
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

  def test_starts_under_rails_server_process
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    raw = Object.new
    raw.define_singleton_method(:wait_for_notify) { |*_args| sleep 0.05 }
    listen_connection = Object.new
    listen_connection.define_singleton_method(:execute) { |_| }
    listen_connection.define_singleton_method(:raw_connection) { raw }
    listen_connection.define_singleton_method(:active?) { true }

    pool = Object.new
    pool.define_singleton_method(:checkout) { listen_connection }
    pool.define_singleton_method(:checkin) { |_| }

    with_rails_server_defined do
      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:rails_console?, false) do
          RecordingStudioMcp::PostgresBus.stub(:rake_task?, false) do
            RecordingStudioMcp::PostgresBus.stub(:rails_runner?, false) do
              RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
                ActiveRecord::Base.stub(:connection_pool, pool) do
                  assert RecordingStudioMcp::PostgresBus.start_allowed?
                  assert Rails.const_defined?(:Server)
                  RecordingStudioMcp::PostgresBus.start!
                  sleep 0.1
                  assert RecordingStudioMcp::PostgresBus.listening?
                  RecordingStudioMcp::PostgresBus.stop!
                end
              end
            end
          end
        end
      end
    end

    refute RecordingStudioMcp::PostgresBus.listening?
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
    clock = 0.0
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
          RecordingStudioMcp::PostgresBus.stub(:monotonic_now, -> { clock }) do
            RecordingStudioMcp::PostgresBus.stub(:interruptible_sleep, ->(*) { clock += 10 }) do
              ActiveRecord::Base.stub(:connection_pool, pool) do
                Rails.stub(:logger, logger) do
                  RecordingStudioMcp::PostgresBus.start!
                  deadline = monotonic_deadline(1)
                  sleep 0.01 while opens < 3 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
                  RecordingStudioMcp::PostgresBus.stop!
                end
              end
            end
          end
        end
      end
    end

    log = log_io.string
    assert_includes log, "LISTEN failed"
    assert_includes log, "IOError: stream closed in another thread"
    assert_includes log, "LISTEN reconnecting"
    assert_operator opens, :>=, 3
    refute RecordingStudioMcp::PostgresBus.listening?
    assert_includes checked_in, listen_connection
  end

  def test_activerecord_errors_during_reconnect_are_recovered
    require "active_record"

    log_io = StringIO.new
    logger = Logger.new(log_io)
    opens = 0
    clock = 0.0
    waits = 0
    raw = Object.new
    raw.define_singleton_method(:wait_for_notify) do |*_args|
      waits += 1
      sleep 0.05
    end
    listen_connection = Object.new
    listen_connection.define_singleton_method(:execute) { |_| }
    listen_connection.define_singleton_method(:raw_connection) { raw }
    listen_connection.define_singleton_method(:active?) { true }

    pool = Object.new
    pool.define_singleton_method(:checkout) do
      opens += 1
      raise ActiveRecord::ConnectionNotEstablished, "database down" if opens <= 3

      listen_connection
    end
    pool.define_singleton_method(:checkin) { |_| }

    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
          RecordingStudioMcp::PostgresBus.stub(:monotonic_now, -> { clock }) do
            RecordingStudioMcp::PostgresBus.stub(:interruptible_sleep, ->(*) { clock += 10 }) do
              ActiveRecord::Base.stub(:connection_pool, pool) do
                Rails.stub(:logger, logger) do
                  RecordingStudioMcp::PostgresBus.start!
                  deadline = monotonic_deadline(2)
                  sleep 0.01 while waits < 1 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
                  assert RecordingStudioMcp::PostgresBus.listening?
                  RecordingStudioMcp::PostgresBus.stop!
                end
              end
            end
          end
        end
      end
    end

    assert_operator opens, :>=, 4
    assert_operator waits, :>=, 1
    assert_includes log_io.string, "ActiveRecord::ConnectionNotEstablished"
    refute RecordingStudioMcp::PostgresBus.listening?
  end

  def test_long_outage_keeps_retrying_then_recovers
    require "active_record"

    opens = 0
    clock = 0.0
    waits = 0
    failure_count = 12
    raw = Object.new
    raw.define_singleton_method(:wait_for_notify) do |*_args|
      waits += 1
      sleep 0.05
    end
    listen_connection = Object.new
    listen_connection.define_singleton_method(:execute) { |_| }
    listen_connection.define_singleton_method(:raw_connection) { raw }
    listen_connection.define_singleton_method(:active?) { true }

    pool = Object.new
    pool.define_singleton_method(:checkout) do
      opens += 1
      raise ActiveRecord::ConnectionTimeoutError, "pool dry" if opens <= failure_count

      listen_connection
    end
    pool.define_singleton_method(:checkin) { |_| }

    delays = []
    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
          RecordingStudioMcp::PostgresBus.stub(:monotonic_now, -> { clock }) do
            RecordingStudioMcp::PostgresBus.stub(:interruptible_sleep, lambda { |delay|
              delays << delay
              clock += 10
            }) do
              ActiveRecord::Base.stub(:connection_pool, pool) do
                RecordingStudioMcp::PostgresBus.start!
                deadline = monotonic_deadline(3)
                sleep 0.01 while waits < 1 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
                assert RecordingStudioMcp::PostgresBus.listening?,
                       "expected recovery after #{failure_count} failures (opens=#{opens}, waits=#{waits})"
                RecordingStudioMcp::PostgresBus.stop!
              end
            end
          end
        end
      end
    end

    assert_operator opens, :>, failure_count
    assert_operator delays.size, :>=, failure_count
    assert_equal RecordingStudioMcp::PostgresBus::RECONNECT_MAX_SECONDS, delays.last
    assert_operator delays.count(RecordingStudioMcp::PostgresBus::RECONNECT_MAX_SECONDS), :>=, 5
    refute RecordingStudioMcp::PostgresBus.listening?
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

  def with_rails_server_defined
    already = defined?(Rails) && Rails.const_defined?(:Server)
    return yield if already

    # Mirror railties: `rails server` defines Rails::Server before boot.
    # Avoid requiring railties' server command in the gem unit suite.
    Rails.const_set(:Server, Class.new)
    yield
  ensure
    Rails.send(:remove_const, :Server) if !already && defined?(Rails) && Rails.const_defined?(:Server)
  end

  def monotonic_deadline(seconds)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  end
end
