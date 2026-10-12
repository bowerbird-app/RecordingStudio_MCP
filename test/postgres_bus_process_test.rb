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
      # Test env skips LISTEN unless forced — process probes opt in explicitly.
      ENV["RECORDING_STUDIO_MCP_POSTGRES_BUS"] = "1"
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
    with_puma_process(workers: 0, solid_queue: false, plugin: false) do |ctx|
      assert_includes ctx[:log], "Listening on", "puma failed to boot:\n#{ctx[:log]}"
      refute_includes ctx[:log], "solid_queue", "Solid Queue plugin should be off:\n#{ctx[:log]}"
      refute_includes ctx[:log], "NoMethodError", ctx[:log]
      await(15, "LISTEN backend", log_path: ctx[:log_path]) { bus_owner_pids.any? }
      assert bus_owner_pids.any?, "expected LISTEN. log:\n#{ctx[:combined]}"
      assert_includes ctx[:combined], "PostgresBus] listening on #{CHANNEL}"
    end
  end

  def test_puma_single_mode_with_plugin_does_not_raise
    with_puma_process(workers: 0, solid_queue: false, plugin: true) do |ctx|
      assert_includes ctx[:log], "Listening on", ctx[:log]
      refute_includes ctx[:log], "NoMethodError", ctx[:log]
      refute_includes ctx[:log], "private method `clustered?'", ctx[:log]
      await(15, "LISTEN with plugin", log_path: ctx[:log_path]) { bus_owner_pids.any? }
      assert_equal 1, bus_owner_pids.size, "expected one LISTEN owner. #{bus_rows.inspect}"
    end
  end

  def test_puma_cluster_plugin_listens_in_workers_not_master
    with_puma_process(workers: 2, solid_queue: false, plugin: true, preload: true) do |ctx|
      assert_includes ctx[:log], "Listening on", ctx[:log]
      refute_includes ctx[:log], "NoMethodError", ctx[:log]
      master_pid = ctx[:pid]
      await(20, "two worker LISTEN owners", log_path: ctx[:log_path]) do
        bus_owner_pids.size >= 2
      end
      owners = bus_owner_pids
      assert_equal 2, owners.size, "expected 2 worker LISTEN pids, got #{owners.inspect}\n#{ctx[:combined]}"
      refute_includes owners, master_pid, "master #{master_pid} must not LISTEN: #{owners.inspect}"

      worker_pids = child_pids(master_pid)
      assert_operator worker_pids.size, :>=, 2, "expected puma workers under #{master_pid}, got #{worker_pids.inspect}"
      owners.each do |owner|
        assert_includes worker_pids, owner, "LISTEN pid #{owner} not a worker of #{master_pid}: #{worker_pids.inspect}"
      end
    end
  end

  def test_puma_single_with_solid_queue_only_puma_listens
    ensure_solid_queue_schema!
    with_puma_process(workers: 0, solid_queue: true, plugin: false) do |ctx|
      assert_includes ctx[:log], "Listening on", ctx[:log]
      refute_includes ctx[:log], "NoMethodError", ctx[:log]
      await(20, "solid queue forked", log_path: ctx[:log_path]) do
        child_pids(ctx[:pid]).any? || File.read(ctx[:log_path]).match?(/Solid Queue|solid_queue/i)
      end
      await(15, "exactly one LISTEN", log_path: ctx[:log_path]) { bus_owner_pids.size == 1 }
      owners = bus_owner_pids
      assert_equal 1, owners.size, "expected one LISTEN from Puma only: #{owners.inspect}\n#{ctx[:combined]}"
      assert_equal ctx[:pid], owners.first, "LISTEN must be the Puma pid #{ctx[:pid]}, got #{owners.inspect}"

      # Solid Queue forks children; none of them should own a LISTEN backend.
      sq_children = child_pids(ctx[:pid])
      assert sq_children.any?, "expected Solid Queue child under Puma #{ctx[:pid]}, got none. log:\n#{ctx[:combined]}"
      sq_children.each do |child|
        refute_includes owners, child, "Solid Queue child #{child} must not LISTEN"
      end
    end
  end

  def test_pre_deploy_env_skips_auto_start_in_server_boot
    script = File.join(DUMMY_ROOT, "tmp/postgres_bus_pre_deploy_probe.rb")
    FileUtils.mkdir_p(File.dirname(script))
    File.write(script, <<~RUBY)
      # frozen_string_literal: true

      ENV["RAILS_ENV"] ||= "test"
      ENV["PRE_DEPLOY"] = "1"
      require "rails"
      Rails.const_set(:Server, Class.new) unless Rails.const_defined?(:Server)
      require_relative "../config/environment"
      bus = RecordingStudioMcp::PostgresBus
      sleep 0.3
      puts "PROBE allowed=\#{bus.start_allowed?} listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
    RUBY

    stdout, status = run_dummy("ruby", script)
    assert status.success?, stdout
    assert_probe stdout, allowed: false, listening: false, enabled: true
  ensure
    FileUtils.rm_f(script) if defined?(script) && script
  end

  # Non-listening publisher (rails runner) NOTIFYs; Puma LISTENER delivers once.
  def test_non_listening_publisher_reaches_puma_listener_once
    # Gem suite runs before test:dummy's db:prepare; Fanout's local deliver path
    # may touch Active Record, so load schema first.
    ensure_dummy_schema!
    counter = File.join(DUMMY_ROOT, "tmp/fanout_delivery_count.txt")
    init = File.join(DUMMY_ROOT, "config/initializers/zzz_fanout_delivery_probe.rb")
    FileUtils.mkdir_p(File.dirname(counter))
    FileUtils.mkdir_p(File.dirname(init))
    FileUtils.rm_f(counter)
    File.write(init, <<~RUBY)
      # frozen_string_literal: true

      Rails.application.config.after_initialize do
        next unless ENV["FANOUT_DELIVERY_PROBE"] == "1"

        path = Rails.root.join("tmp/fanout_delivery_count.txt")
        notifier = RecordingStudioMcp::Notifier
        original = notifier.method(:deliver_local)
        notifier.define_singleton_method(:deliver_local) do |**kwargs|
          File.open(path, "a") do |file|
            file.puts("deliver \#{kwargs[:event_name]} \#{kwargs[:recording_id]} pid=\#{Process.pid}")
          end
          original.call(**kwargs)
        end
      end
    RUBY

    with_puma_process(workers: 0, solid_queue: false, plugin: true,
                      extra_env: { "FANOUT_DELIVERY_PROBE" => "1" }) do |ctx|
      assert_includes ctx[:log], "Listening on", ctx[:log]
      await(15, "LISTEN ready", log_path: ctx[:log_path]) { bus_owner_pids.any? }
      File.write(counter, "")

      stdout, status = run_dummy(
        "bin/rails", "runner",
        <<~RUBY
          bus = RecordingStudioMcp::PostgresBus
          raise "publisher must not listen" if bus.listening?
          RecordingStudioMcp::Fanout.publish(
            event_name: "recording updated",
            recording_id: "fanout-cross-process"
          )
          puts "PUBLISHER listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
        RUBY
      )
      assert status.success?, stdout
      assert_includes stdout, "PUBLISHER listening=false"
      assert_includes stdout, "enabled=true"

      await(15, "one fanout delivery", log_path: ctx[:log_path]) do
        File.exist?(counter) && File.readlines(counter).grep(/fanout-cross-process/).size == 1
      end
      lines = File.readlines(counter).map(&:strip).reject(&:empty?)
      assert_equal 1, lines.size, "expected exactly one delivery, got #{lines.inspect}\n#{ctx[:combined]}"
      assert_match(/fanout-cross-process/, lines.first)
      assert_match(/pid=#{ctx[:pid]}\b/, lines.first)
    end
  ensure
    FileUtils.rm_f(init) if defined?(init) && init
    FileUtils.rm_f(counter) if defined?(counter) && counter
  end

  # Listening process NOTIFYs and receives via LISTEN — must not also deliver_local.
  def test_listening_process_fanout_does_not_double_deliver
    ensure_dummy_schema!
    script = File.join(DUMMY_ROOT, "tmp/postgres_bus_fanout_once_probe.rb")
    FileUtils.mkdir_p(File.dirname(script))
    File.write(script, <<~RUBY)
      # frozen_string_literal: true

      require "timeout"

      ENV["RAILS_ENV"] ||= "test"
      ENV["RECORDING_STUDIO_MCP_POSTGRES_BUS"] = "1"
      require "rails"
      Rails.const_set(:Server, Class.new) unless Rails.const_defined?(:Server)
      require_relative "../config/environment"

      bus = RecordingStudioMcp::PostgresBus
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      until bus.listening? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.05
      end
      raise "bus not listening" unless bus.listening?

      deliveries = []
      notifier = RecordingStudioMcp::Notifier
      original = notifier.method(:deliver_local)
      notifier.define_singleton_method(:deliver_local) do |**kwargs|
        deliveries << [kwargs[:event_name].to_s, kwargs[:recording_id].to_s]
        original.call(**kwargs)
      end

      RecordingStudioMcp::Fanout.publish(
        event_name: "recording updated",
        recording_id: "fanout-once"
      )

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      until deliveries.any? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.05
      end
      sleep 0.3

      puts "DELIVER_COUNT=\#{deliveries.size}"
      puts "DELIVERIES=\#{deliveries.inspect}"
      bus.stop!
    RUBY

    stdout, status = run_dummy("ruby", script)
    assert status.success?, stdout
    assert_includes stdout, "DELIVER_COUNT=1"
    assert_includes stdout, '["recording updated", "fanout-once"]'
  ensure
    FileUtils.rm_f(script) if defined?(script) && script
  end

  # Standalone bin/jobs: $PROGRAM_NAME basename is "jobs". LISTEN stays off; NOTIFY still works via Fanout.
  def test_bin_jobs_program_name_skips_auto_start
    script = File.join(DUMMY_ROOT, "tmp/postgres_bus_bin_jobs_probe.rb")
    FileUtils.mkdir_p(File.dirname(script))
    File.write(script, <<~RUBY)
      # frozen_string_literal: true

      $PROGRAM_NAME = File.expand_path("../bin/jobs", __dir__)
      ENV["RAILS_ENV"] ||= "test"
      require_relative "../config/environment"
      bus = RecordingStudioMcp::PostgresBus
      sleep 0.3
      puts "PROBE allowed=\#{bus.start_allowed?} listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
      puts "PROGRAM=\#{File.basename($PROGRAM_NAME)}"
    RUBY

    stdout, status = run_dummy("ruby", script)
    assert status.success?, stdout
    assert_includes stdout, "PROGRAM=jobs"
    assert_probe stdout, allowed: false, listening: false, enabled: true
  ensure
    FileUtils.rm_f(script) if defined?(script) && script
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
    cleaned.delete("PRE_DEPLOY")
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

  def with_puma_process(workers:, solid_queue:, plugin:, preload: false, extra_env: {})
    port = free_port
    log_path = File.join(DUMMY_ROOT, "tmp/postgres_bus_puma_#{workers}_#{solid_queue}_#{plugin}.log")
    rails_log = File.join(DUMMY_ROOT, "log/test.log")
    config_path = File.join(DUMMY_ROOT, "tmp/puma_postgres_bus_#{workers}_#{plugin}.rb")
    FileUtils.mkdir_p(File.dirname(log_path))
    FileUtils.mkdir_p(File.dirname(rails_log))
    FileUtils.rm_f(log_path)
    File.write(rails_log, "")
    write_puma_config(config_path, workers: workers, plugin: plugin, preload: preload, solid_queue: solid_queue)

    pid = nil
    Bundler.with_unbundled_env do
      env = dummy_env.merge(
        "PORT" => port.to_s,
        "RAILS_ENV" => "test",
        # RAILS_ENV=test skips LISTEN unless forced; Puma probes need the bus.
        RecordingStudioMcp::PostgresBus::START_ENV => "1",
        "WEB_CONCURRENCY" => workers.to_s,
        "RAILS_MAX_THREADS" => "5"
      )
      if solid_queue
        env["SOLID_QUEUE_IN_PUMA"] = "1"
        env["SOLID_QUEUE_SKIP_RECURRING"] = "1"
        env["JOB_CONCURRENCY"] = "1"
        env["SOLID_QUEUE_CONFIG"] = @solid_queue_config if @solid_queue_config
        env["SOLID_QUEUE_RECURRING_SCHEDULE"] = @solid_queue_recurring if @solid_queue_recurring
      else
        env.delete("SOLID_QUEUE_IN_PUMA")
        env.delete("SOLID_QUEUE_SKIP_RECURRING")
        env.delete("SOLID_QUEUE_CONFIG")
        env.delete("SOLID_QUEUE_RECURRING_SCHEDULE")
      end
      env.merge!(extra_env)
      pid = Process.spawn(
        env,
        "bundle", "exec", "puma", "-C", config_path, "-b", "tcp://127.0.0.1:#{port}",
        chdir: DUMMY_ROOT,
        out: log_path,
        err: log_path
      )
    end

    await(45, "puma Listening on", log_path: log_path) do
      File.exist?(log_path) && File.read(log_path).include?("Listening on")
    end
    # Workers need a moment after "Listening on" in cluster mode.
    sleep(workers.positive? ? 2 : 0.5)
    log = File.read(log_path)
    combined = "#{log}\n#{File.read(rails_log)}"
    yield({ pid: pid, log: log, log_path: log_path, rails_log: rails_log, combined: combined, port: port })
  ensure
    FileUtils.rm_f(config_path) if defined?(config_path) && config_path
    if defined?(pid) && pid
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end

  def write_puma_config(path, workers:, plugin:, preload:, solid_queue:)
    File.write(path, <<~RUBY)
      # frozen_string_literal: true

      threads 3, 3
      workers #{workers}
      #{'preload_app!' if preload || workers.positive?}
      plugin :tmp_restart
      #{'plugin :solid_queue' if solid_queue}
      #{'plugin :recording_studio_mcp_postgres_bus' if plugin}
    RUBY
  end

  def ensure_dummy_schema!
    return if recordings_table_present?

    stdout, status = run_dummy("bin/rails", "db:schema:load")
    assert status.success?, "failed to load dummy schema:\n#{stdout}"
    assert recordings_table_present?, "recording_studio_recordings missing after schema:load"
  end

  def recordings_table_present?
    sql = "SELECT 1 FROM information_schema.tables WHERE table_name = 'recording_studio_recordings'"
    stdout, status = Open3.capture2e(psql_env, "psql", database_url, "-At", "-c", sql)
    status.success? && stdout.strip == "1"
  end

  def ensure_solid_queue_schema!
    write_solid_queue_config_files!
    unless solid_queue_table_present?
      stdout, status = run_dummy(
        "bin/rails", "runner",
        <<~RUBY
          path = Gem.loaded_specs.fetch("solid_queue").full_gem_path
          load File.join(path, "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
          # Schema.define stamps schema_migrations (version 1). That makes a later
          # dummy db:prepare skip schema.rb, where Oauth create tables live.
          conn = ActiveRecord::Base.connection
          conn.drop_table(:schema_migrations, if_exists: true)
          conn.drop_table(:ar_internal_metadata, if_exists: true)
          puts "SOLID_QUEUE_SCHEMA_OK"
        RUBY
      )
      assert status.success?, "failed to load Solid Queue schema:\n#{stdout}"
      assert solid_queue_table_present?, "solid_queue_processes missing after schema load"
    end
    clear_solid_queue_schema_migration_stamp!
  end

  # Undo a Schema.define(version: 1) stamp left by queue_schema.rb so
  # test:dummy's db:prepare still loads schema.rb on a fresh CI database.
  def clear_solid_queue_schema_migration_stamp!
    sql = <<~SQL.tr("\n", " ")
      SELECT COALESCE(string_agg(version, ',' ORDER BY version), '')
      FROM schema_migrations
    SQL
    stdout, status = Open3.capture2e(psql_env, "psql", database_url, "-At", "-c", sql)
    return unless status.success?
    return unless stdout.strip == "1"

    Open3.capture2e(psql_env, "psql", database_url, "-c",
                    "DROP TABLE IF EXISTS schema_migrations, ar_internal_metadata CASCADE")
  end

  # Minimal Solid Queue config so SOLID_QUEUE_IN_PUMA can fork a supervisor.
  # Uses the primary DB (no separate queue DB in test). Paths are under tmp/.
  def write_solid_queue_config_files!
    dir = File.join(DUMMY_ROOT, "tmp/solid_queue_config")
    FileUtils.mkdir_p(dir)
    queue_yml = File.join(dir, "queue.yml")
    recurring_yml = File.join(dir, "recurring.yml")
    File.write(queue_yml, <<~YAML)
      default: &default
        dispatchers:
          - polling_interval: 1
            batch_size: 500
        workers:
          - queues: "*"
            threads: 1
            processes: 1
            polling_interval: 0.1

      test:
        <<: *default
    YAML
    File.write(recurring_yml, <<~YAML)
      test:
    YAML
    @solid_queue_config = queue_yml
    @solid_queue_recurring = recurring_yml
  end

  def solid_queue_table_present?
    sql = "SELECT 1 FROM information_schema.tables WHERE table_name = 'solid_queue_processes'"
    stdout, status = Open3.capture2e(psql_env, "psql", database_url, "-At", "-c", sql)
    status.success? && stdout.strip == "1"
  end

  def bus_rows
    prefix = RecordingStudioMcp::PostgresBus::APPLICATION_NAME_PREFIX
    # Require an active LISTEN query so a master's checked-in pool connection
    # that still has application_name after UNLISTEN is not counted.
    sql = <<~SQL.tr("\n", " ")
      SELECT pid, application_name, state, left(query, 80)
      FROM pg_stat_activity
      WHERE pid <> pg_backend_pid()
        AND application_name LIKE '#{prefix}:%'
        AND query ILIKE '%LISTEN%#{CHANNEL}%'
    SQL
    stdout, status = Open3.capture2e(psql_env, "psql", database_url, "-At", "-F", "|", "-c", sql)
    return [] unless status.success?

    stdout.lines.map(&:strip).reject(&:empty?)
  end

  def bus_owner_pids
    prefix = RecordingStudioMcp::PostgresBus::APPLICATION_NAME_PREFIX
    bus_rows.filter_map do |row|
      app = row.split("|")[1].to_s
      match = app.match(/\A#{Regexp.escape(prefix)}:(\d+)\z/)
      match && match[1].to_i
    end.uniq
  end

  def child_pids(parent_pid)
    stdout, status = Open3.capture2e("pgrep", "-P", parent_pid.to_s)
    return [] unless status.success?

    stdout.lines.map(&:strip).reject(&:empty?).map(&:to_i)
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
