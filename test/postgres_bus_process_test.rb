# frozen_string_literal: true

require "test_helper"
require "open3"
require "fileutils"

# Unstubbed subprocess checks: real bin/rails runner, rake, and console in the
# dummy app must not start PostgresBus (unless the env flag forces it).
class PostgresBusProcessTest < Minitest::Test
  DUMMY_ROOT = File.expand_path("dummy", __dir__)
  PROBE_LINE = /PROBE allowed=(true|false) listening=(true|false) enabled=(true|false)/

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

  def test_server_like_boot_starts_postgres_bus
    script = File.join(DUMMY_ROOT, "tmp/postgres_bus_server_probe.rb")
    FileUtils.mkdir_p(File.dirname(script))
    File.write(script, <<~RUBY)
      # frozen_string_literal: true

      ENV["RAILS_ENV"] ||= "test"
      require "rails"
      # Same constant `rails server` defines before boot (railties ServerCommand).
      Rails.const_set(:Server, Class.new) unless Rails.const_defined?(:Server)
      require_relative "../config/environment"

      ActiveRecord::Base.connection.select_value("SELECT 1")
      RecordingStudioMcp::PostgresBus.start!
      bus = RecordingStudioMcp::PostgresBus
      puts "PROBE allowed=\#{bus.start_allowed?} listening=\#{bus.listening?} enabled=\#{bus.enabled?}"
      puts "SERVER=\#{Rails.const_defined?(:Server)}"
      puts "RUNNER=\#{defined?(Rails::Command::RunnerCommand).inspect}"
      bus.stop!
    RUBY

    stdout, status = run_dummy("ruby", script)

    assert status.success?, stdout
    assert_includes stdout, "SERVER=true"
    assert_includes stdout, "RUNNER=nil"
    assert_probe stdout, allowed: true, listening: true, enabled: true
  ensure
    FileUtils.rm_f(script) if defined?(script) && script
  end

  private

  def run_dummy(*command, stdin_data: nil)
    env = {
      "BUNDLE_GEMFILE" => File.join(DUMMY_ROOT, "Gemfile"),
      "RAILS_ENV" => "test",
      "DATABASE_URL" => database_url,
      "BOOTSNAP_CACHE_DIR" => File.join(DUMMY_ROOT, "tmp/cache")
    }

    Bundler.with_unbundled_env do
      cleaned = ENV.to_h.merge(env)
      cleaned.delete(RecordingStudioMcp::PostgresBus::START_ENV)
      Open3.capture2e(cleaned, "bundle", "exec", *command, chdir: DUMMY_ROOT, stdin_data: stdin_data)
    end
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
end
