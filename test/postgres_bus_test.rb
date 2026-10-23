# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"
require "rake"

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
        Rake.stub(:application, rake_app) do
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
    raw.define_singleton_method(:wait_for_notify) { |*_args| sleep 0.05 }
    connection = Object.new
    connection.define_singleton_method(:raw_connection) { raw }
    connection.define_singleton_method(:active?) { raise IOError, "stream closed in another thread" }
    executed = []
    connection.define_singleton_method(:execute) { |sql| executed << sql }

    checked_in = []
    pool = Object.new
    pool.define_singleton_method(:checkout) { connection }
    pool.define_singleton_method(:checkin) { |conn| checked_in << conn }

    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        RecordingStudioMcp::PostgresBus.stub(:wake_listen_loop, nil) do
          ActiveRecord::Base.stub(:connection_pool, pool) do
            RecordingStudioMcp::PostgresBus.start!
            sleep 0.1
            RecordingStudioMcp::PostgresBus.stop!
            RecordingStudioMcp::PostgresBus.stop!
          end
        end
      end
    end

    refute_includes executed, "UNLISTEN #{RecordingStudioMcp::PostgresBus::CHANNEL}"
    assert_equal [connection], checked_in
    refute RecordingStudioMcp::PostgresBus.listening?
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
    entered = Queue.new
    gate = Queue.new
    raw = Object.new
    raw.define_singleton_method(:wait_for_notify) do |*_args|
      entered << true
      gate.pop
    end

    connection = Object.new
    connection.define_singleton_method(:raw_connection) { raw }
    connection.define_singleton_method(:active?) { true }
    connection.define_singleton_method(:execute) { |_| }

    checked_in = []
    pool = Object.new
    pool.define_singleton_method(:checkout) { connection }
    pool.define_singleton_method(:checkin) { |conn| checked_in << conn }

    log_io = StringIO.new
    logger = Logger.new(log_io)

    RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
      RecordingStudioMcp::PostgresBus.stub(:start_allowed?, true) do
        ActiveRecord::Base.stub(:connection_pool, pool) do
          Rails.stub(:logger, logger) do
            RecordingStudioMcp::PostgresBus.start!
            entered.pop
            RecordingStudioMcp::PostgresBus.stop!
            assert_empty checked_in
            assert_includes log_io.string, "did not stop within"
            gate << true
            deadline = monotonic_deadline(3)
            sleep 0.01 while checked_in.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          end
        end
      end
    end

    assert_equal [connection], checked_in
  end

  def with_runner_command_defined
    already = defined?(Rails) && Rails.const_defined?(:Command) &&
              Rails::Command.const_defined?(:RunnerCommand)
    return yield if already

    Rails.const_set(:Command, Module.new) unless defined?(Rails) && Rails.const_defined?(:Command)
    Rails::Command.const_set(:RunnerCommand, Class.new)
    yield
  ensure
    Rails::Command.send(:remove_const, :RunnerCommand) if !already && defined?(Rails) &&
                                                          Rails.const_defined?(:Command) &&
                                                          Rails::Command.const_defined?(:RunnerCommand)
  end

  def with_rails_server_defined
    already = defined?(Rails) && Rails.const_defined?(:Server)
    return yield if already

    Rails.const_set(:Server, Class.new)
    yield
  ensure
    Rails.send(:remove_const, :Server) if !already && defined?(Rails) && Rails.const_defined?(:Server)
  end

  def monotonic_deadline(seconds)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  end
end
