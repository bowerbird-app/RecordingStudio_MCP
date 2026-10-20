# frozen_string_literal: true

require "test_helper"
require "active_record"

class UsageSummariesMigrationTest < Minitest::Test
  MIGRATION_PATH = File.expand_path(
    "../db/migrate/20261020120000_create_recording_studio_mcp_usage_summaries.rb",
    __dir__
  )
  DUMMY_MIGRATION_PATH = File.expand_path(
    "dummy/db/migrate/20261020120000_create_recording_studio_mcp_usage_summaries.rb",
    __dir__
  )

  def setup
    require MIGRATION_PATH
  end

  def test_source_mirrors_api_dual_connection_install
    source = File.read(MIGRATION_PATH)

    assert_includes source, "each_usage_log_connection"
    assert_includes source, "RecordingStudioMcp::UsageLog.connection"
    assert_includes source, "RecordingStudioLogs::Schema.install_runs!(conn)"
    assert_includes source, "connection: conn"
    refute_includes source, "RecordingStudioLogs::Schema.install_runs!(connection)"
    refute_includes source, "name: \"index_rs_mcp_usage_day_summaries_identity\"\n    )"
    assert_equal File.read(MIGRATION_PATH), File.read(DUMMY_MIGRATION_PATH)
  end

  def test_installs_on_primary_and_usage_log_connections_when_they_differ
    primary = stub_connection("primary")
    logging = stub_connection("logging")
    migration = CreateRecordingStudioMcpUsageSummaries.new
    migration.define_singleton_method(:connection) { primary }
    migration.define_singleton_method(:logging_connection) { logging }

    installed = []
    indexed = []
    RecordingStudioLogs::Schema.stub(:install_runs!, ->(conn) { installed << conn }) do
      RecordingStudioLogs::Schema.stub(:summary_index, lambda { |*_args, **kwargs|
        indexed << kwargs.fetch(:connection)
      }) do
        migration.send(:create_summary_tables, primary)
        migration.send(:create_summary_tables, logging)
      end
    end

    assert_equal [primary, logging], installed
    assert_equal [primary, logging], indexed
    assert_equal %w[recording_studio_mcp_usage_day_summaries], primary.created_tables
    assert_equal %w[recording_studio_mcp_usage_day_summaries], logging.created_tables
    assert_equal %w[recording_studio_mcp_usage_day_metric_rollups], primary.views
    assert_equal %w[recording_studio_mcp_usage_day_metric_rollups], logging.views
  end

  def test_up_installs_on_each_distinct_connection
    primary = stub_connection("primary")
    logging = stub_connection("logging")
    migration = CreateRecordingStudioMcpUsageSummaries.new
    migration.define_singleton_method(:connection) { primary }
    migration.define_singleton_method(:logging_connection) { logging }

    yielded = []
    migration.define_singleton_method(:create_summary_tables) { |conn| yielded << conn }
    migration.up
    assert_equal [primary, logging], yielded
  end

  def test_each_usage_log_connection_skips_the_same_connection_twice
    shared = stub_connection("primary")
    migration = CreateRecordingStudioMcpUsageSummaries.new
    migration.define_singleton_method(:connection) { shared }
    migration.define_singleton_method(:logging_connection) { shared }

    yielded = []
    migration.send(:each_usage_log_connection) { |conn| yielded << conn }
    assert_equal [shared], yielded
  end

  def test_each_usage_log_connection_yields_distinct_connections
    primary = stub_connection("primary")
    logging = stub_connection("logging")
    migration = CreateRecordingStudioMcpUsageSummaries.new
    migration.define_singleton_method(:connection) { primary }
    migration.define_singleton_method(:logging_connection) { logging }

    yielded = []
    migration.send(:each_usage_log_connection) { |conn| yielded << conn }
    assert_equal [primary, logging], yielded
  end

  private

  def stub_connection(name)
    raw = Object.new
    pool = Struct.new(:db_config).new(Struct.new(:name).new(name))
    ConnectionStub.new(pool:, raw:)
  end

  class ConnectionStub
    attr_reader :pool, :raw_connection, :created_tables, :views, :indexes

    def initialize(pool:, raw:)
      @pool = pool
      @raw_connection = raw
      @created_tables = []
      @views = []
      @indexes = []
    end

    def data_source_exists?(_name)
      false
    end

    def create_table(name, **)
      @created_tables << name
    end

    def add_index(table, columns, **options)
      @indexes << [table, columns, options]
    end

    def quote_table_name(name)
      name
    end

    def execute(sql)
      match = sql.to_s.match(/CREATE VIEW (\S+)/)
      @views << match[1] if match
    end
  end
end
