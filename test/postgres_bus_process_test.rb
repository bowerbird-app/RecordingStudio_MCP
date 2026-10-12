# frozen_string_literal: true

require "test_helper"
require "open3"
require "fileutils"
require "socket"
require "json"
require "uri"

# Unstubbed subprocess checks: real bin/rails runner, rake, and console in the
# dummy app must not start PostgresBus (unless the env flag forces it). Server
# boot must auto-start without a prior query (enabled? no longer needs connected?).
class PostgresBusProcessTest < Minitest::Test
  DUMMY_ROOT = File.expand_path("dummy", __dir__)
  PROBE_LINE = /PROBE allowed=(true|false) listening=(true|false) enabled=(true|false)/
  CHANNEL = RecordingStudioMcp::PostgresBus::CHANNEL
  # Match Rakefile dummy_bundle_env: clear parent Bundler so the dummy Gemfile wins.
  BUNDLE_CLEAR_KEYS = %w[
    BUNDLE_APP_CONFIG BUNDLE_BIN_PATH BUNDLE_GEMFILE BUNDLE_LOCKFILE
    BUNDLE_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYLIB RUBYOPT
  ].freeze

  def test_rails_runner_does_not_start_postgres_bus
    code = [
      'ActiveRecord::Base.connection.select_value("SELECT 1")',
      "RecordingStudioMcp::PostgresBus.start!",
      "bus = RecordingStudioMcp::PostgresBus",
      'puts "PROBE allowed=#{bus.start_allowed?} listening=#{bus.listening?} enabled=#{bus.enabled?}"',
      'puts "RUNNER_DEFINED=#{defined?(Rails::Command::RunnerCommand).inspect}"'
    ].join("; ")

    stdout, status = run_dummy("bin/rails", "runner", code)

    assert status.success?, stdout
    assert_includes stdout, 'RUNNER_DEFINED="constant"'
    assert_probe stdout, allowed: false, listening: false, enabled: true
  end

  def test_rake_task_does_not_start_postgres_bus
    rake_file = File.join(DUMMY_ROOT, "lib/tasks/postgres_bus_process_probe.rake")
    FileUtils.mkdir_p(File.dirname(rake_file))
    File.write(rake_file, <<~RAKE)
      # frozen_string_literal: true

      task postgres_bus_process_probe: :environment do
        ActiveRecord::Base.connection.select_value("SELECT 1")
        RecordingStudioMcp::PostgresBus.start!
        bus = RecordingStudioMcp::PostgresBus
        puts "PROBE allowed=\#{bus.start_allowed?} listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
        puts "RAKE_TASKS=\#{Rake.application.top_level_tasks.inspect}"
      end
    RAKE

    stdout, status = run_dummy("bin/rake", "postgres_bus_process_probe")

    assert status.success?, stdout
    assert_match(/RAKE_TASKS=\[.*postgres_bus_process_probe.*\]/, stdout)
    assert_probe stdout, allowed: false, listening: false, enabled: true
  ensure
    FileUtils.rm_f(rake_file) if defined?(rake_file) && rake_file
  end

  def test_rails_console_does_not_start_postgres_bus
    script = <<~RUBY
      ActiveRecord::Base.connection.select_value("SELECT 1")
      RecordingStudioMcp::PostgresBus.start!
      bus = RecordingStudioMcp::PostgresBus
      puts "PROBE allowed=\#{bus.start_allowed?} listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
      puts "CONSOLE=\#{Rails.const_defined?(:Console)}"
      exit
    RUBY

    stdout, status = run_dummy("bin/rails", "console", stdin_data: script)

    assert status.success?, stdout
    assert_includes stdout, "CONSOLE=true"
    assert_probe stdout, allowed: false, listening: false, enabled: true
  end

  # Loads the env as a server with NO prior query and NO manual start!.
  # after_initialize must auto-start; then a NOTIFY must be received.
  def test_server_boot_auto_starts_without_prior_query
    script = File.join(DUMMY_ROOT, "tmp/postgres_bus_server_autostart_probe.rb")
    FileUtils.mkdir_p(File.dirname(script))
    boot_init = File.join(DUMMY_ROOT, "config/initializers/zzz_postgres_bus_autostart_probe.rb")
    FileUtils.mkdir_p(File.dirname(boot_init))
    File.write(boot_init, <<~RUBY)
      # frozen_string_literal: true

      # Runs among after_initialize callbacks. The engine registers start! first
      # (engine load precedes initializers). We record pool state immediately in
      # this callback; start! only opens a connection on the listen thread, so
      # connected? is still usually false here when the pool was lazy at boot.
      Rails.application.config.after_initialize do
        bus = RecordingStudioMcp::PostgresBus
        File.write(
          Rails.root.join("tmp/postgres_bus_autostart_boot.txt"),
          [
            "connected=\#{ActiveRecord::Base.connected?}",
            "enabled=\#{bus.enabled?}",
            "allowed=\#{bus.start_allowed?}",
            "listening=\#{bus.listening?}"
          ].join("\\n")
        )
      end
    RUBY

    script = File.join(DUMMY_ROOT, "tmp/postgres_bus_server_autostart_probe.rb")
    FileUtils.mkdir_p(File.dirname(script))
    File.write(script, <<~RUBY)
      # frozen_string_literal: true

      require "timeout"
      require "json"

      ENV["RAILS_ENV"] ||= "test"
      require "rails"
      # Same constant `rails server` defines before boot (railties ServerCommand).
      Rails.const_set(:Server, Class.new) unless Rails.const_defined?(:Server)
      require_relative "../config/environment"

      bus = RecordingStudioMcp::PostgresBus
      # No ActiveRecord query from this script before waiting on auto-start.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      until bus.listening? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.05
      end

      received = Queue.new
      notifier = RecordingStudioMcp::Notifier
      original = notifier.method(:deliver_local)
      notifier.define_singleton_method(:deliver_local) do |event_name:, recording_id:|
        received << [event_name.to_s, recording_id.to_s]
        original.call(event_name: event_name, recording_id: recording_id)
      end

      payload = { "event" => "recording updated", "id" => "autostart-probe" }.to_json
      ActiveRecord::Base.connection.execute(
        "NOTIFY \#{RecordingStudioMcp::PostgresBus::CHANNEL}, \#{ActiveRecord::Base.connection.quote(payload)}"
      )

      got = begin
        Timeout.timeout(5) { received.pop }
      rescue Timeout::Error
        nil
      end

      boot = File.read(Rails.root.join("tmp/postgres_bus_autostart_boot.txt"))
      puts "BOOT_PROBE"
      puts boot
      puts "PROBE allowed=\#{bus.start_allowed?} listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
      puts "SERVER=\#{Rails.const_defined?(:Server)}"
      puts "RUNNER=\#{defined?(Rails::Command::RunnerCommand).inspect}"
      puts "NOTIFY_RECEIVED=\#{!got.nil?}"
      puts "NOTIFY_PAYLOAD=\#{got.inspect}"
      bus.stop!
    RUBY

    stdout, status = run_dummy("ruby", script)

    assert status.success?, stdout
    assert_includes stdout, "enabled=true"
    assert_includes stdout, "allowed=true"
    assert_includes stdout, "SERVER=true"
    assert_includes stdout, "RUNNER=nil"
    assert_includes stdout, "NOTIFY_RECEIVED=true"
    assert_probe stdout, allowed: true, listening: true, enabled: true
  ensure
    FileUtils.rm_f(script) if defined?(script) && script
    FileUtils.rm_f(boot_init) if defined?(boot_init) && boot_init
    FileUtils.rm_f(File.join(DUMMY_ROOT, "tmp/postgres_bus_autostart_boot.txt"))
  end

  # Boots real Puma in single mode and asserts a LISTEN backend exists with no
  # prior HTTP/AR query from us. Skips the Solid Queue plugin (empty string is
  # truthy in Ruby — omit the env var entirely).
  def test_puma_single_mode_listens_without_prior_query
    port = free_port
    log_path = File.join(DUMMY_ROOT, "tmp/postgres_bus_puma_probe.log")
    rails_log = File.join(DUMMY_ROOT, "log/test.log")
    FileUtils.mkdir_p(File.dirname(log_path))
    FileUtils.mkdir_p(File.dirname(rails_log))
    FileUtils.rm_f(log_path)
    # Truncate so we only see lines from this boot.
    File.write(rails_log, "")

    pid = nil
    # Build env inside with_unbundled_env so parent gem BUNDLE_* does not leak
    # into the dummy Puma process (that broke CI boot).
    Bundler.with_unbundled_env do
      env = dummy_env.merge(
        "PORT" => port.to_s,
        "RAILS_ENV" => "test",
        "WEB_CONCURRENCY" => "0",
        "RAILS_MAX_THREADS" => "5"
      )
      env.delete("SOLID_QUEUE_IN_PUMA")
      pid = Process.spawn(
        env,
        "bundle", "exec", "puma", "-C", "config/puma.rb", "-b", "tcp://127.0.0.1:#{port}",
        chdir: DUMMY_ROOT,
        out: log_path,
        err: log_path
      )
    end

    await(30, "puma Listening on", log_path: log_path) do
      File.exist?(log_path) && File.read(log_path).include?("Listening on")
    end
    log = File.read(log_path)
    assert_includes log, "Listening on", "puma failed to boot:\n#{log}"
    refute_includes log, "solid_queue", "Solid Queue plugin should be off:\n#{log}"

    await(15, "LISTEN backend", log_path: log_path) { listen_backends.any? }

    backends = listen_backends
    rails_tail = File.read(rails_log)
    assert backends.any?,
           "expected LISTEN on #{CHANNEL}, got none.\npuma:\n#{log}\nrails:\n#{rails_tail}"

    listen_line = "PostgresBus] listening on #{CHANNEL}"
    await(10, "PostgresBus listening log", log_path: log_path) do
      File.read(log_path).include?(listen_line) || File.read(rails_log).include?(listen_line)
    end
    combined = "#{File.read(log_path)}\n#{File.read(rails_log)}"
    assert_includes combined, listen_line, "missing boot info log:\n#{combined}"

    publish_notify("puma-probe")
    sleep 0.5
    assert listen_backends.any?, "LISTEN disappeared after NOTIFY. log:\n#{combined}"
  ensure
    if defined?(pid) && pid
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end

  private

  def run_dummy(*command, stdin_data: nil)
    Bundler.with_unbundled_env do
      Open3.capture2e(dummy_env, "bundle", "exec", *command, chdir: DUMMY_ROOT, stdin_data: stdin_data)
    end
  end

  def dummy_env
    cleaned = ENV.to_h
    BUNDLE_CLEAR_KEYS.each { |key| cleaned.delete(key) }
    cleaned.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    cleaned.delete("SOLID_QUEUE_IN_PUMA")
    cleaned.merge(
      "BUNDLE_GEMFILE" => File.join(DUMMY_ROOT, "Gemfile"),
      "RAILS_ENV" => "test",
      "DATABASE_URL" => database_url,
      "BOOTSNAP_CACHE_DIR" => File.join(DUMMY_ROOT, "tmp/cache")
    )
  end

  def database_url
    ENV.fetch(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5432/recording_studio_mcp_test"
    )
  end

  def assert_probe(stdout, allowed:, listening:, enabled:)
    match = stdout.match(PROBE_LINE)
    assert match, "expected PROBE line in:\n#{stdout}"
    assert_equal allowed.to_s, match[1], "allowed mismatch in:\n#{stdout}"
    assert_equal listening.to_s, match[2], "listening mismatch in:\n#{stdout}"
    assert_equal enabled.to_s, match[3], "enabled mismatch in:\n#{stdout}"
  end

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def await(seconds, label, log_path: nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      return if yield

      sleep 0.1
    end
    detail = log_path && File.exist?(log_path) ? "\n#{File.read(log_path)}" : ""
    flunk "timed out waiting for #{label} after #{seconds}s#{detail}"
  end

  def listen_backends
    sql = <<~SQL.tr("\n", " ")
      SELECT pid, state, left(query, 120) AS query
      FROM pg_stat_activity
      WHERE pid <> pg_backend_pid()
        AND query ILIKE '%LISTEN%#{CHANNEL}%'
    SQL
    stdout, status = Open3.capture2e(psql_env, "psql", database_url, "-At", "-F", "|", "-c", sql)
    return [] unless status.success?

    stdout.lines.map(&:strip).reject(&:empty?)
  end

  def publish_notify(recording_id)
    payload = JSON.generate({ "event" => "recording updated", "id" => recording_id.to_s })
    quoted = payload.gsub("'", "''")
    sql = "NOTIFY #{CHANNEL}, '#{quoted}'"
    stdout, status = Open3.capture2e(psql_env, "psql", database_url, "-c", sql)
    assert status.success?, "NOTIFY failed: #{stdout}"
  end

  def psql_env
    uri = URI.parse(database_url.sub(/\Apostgres:/, "postgresql:"))
    {
      "PGPASSWORD" => uri.password || "postgres",
      "PGUSER" => uri.user || "postgres",
      "PGHOST" => uri.host || "localhost",
      "PGPORT" => (uri.port || 5432).to_s
    }
  end
end
