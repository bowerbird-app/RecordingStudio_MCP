# frozen_string_literal: true

class CreateRecordingStudioMcpUsageSummaries < ActiveRecord::Migration[8.1]
  COUNTS_TABLE = "recording_studio_mcp_usage_day_summaries"
  ROLLUP_VIEW = "recording_studio_mcp_usage_day_metric_rollups"

  def up
    each_usage_log_connection { |conn| create_summary_tables(conn) }
  end

  def down
    each_usage_log_connection { |conn| drop_summary_tables(conn) }
  end

  private

  def each_usage_log_connection
    seen = []
    [connection, logging_connection].compact.each do |conn|
      identity = [conn.pool.db_config.name, conn.raw_connection.object_id]
      next if seen.include?(identity)

      seen << identity
      yield conn
    end
  end

  def logging_connection
    return unless defined?(RecordingStudioMcp::UsageLog)

    RecordingStudioMcp::UsageLog.connection
  rescue StandardError
    nil
  end

  def create_summary_tables(conn)
    RecordingStudioLogs::Schema.install_runs!(conn)

    unless conn.data_source_exists?(COUNTS_TABLE)
      conn.create_table COUNTS_TABLE, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.date :day, null: false
        t.string :method_name, null: false
        t.string :subject_name, null: false, default: ""
        t.boolean :failed, null: false, default: false
        t.boolean :rate_limited, null: false, default: false
        t.bigint :call_count, null: false, default: 0
        t.timestamps
      end
      RecordingStudioLogs::Schema.summary_index(
        COUNTS_TABLE,
        %i[day method_name subject_name failed rate_limited],
        name: "index_rs_mcp_usage_day_summaries_identity",
        connection: conn
      )
      conn.add_index COUNTS_TABLE, :day, name: "index_rs_mcp_usage_day_summaries_on_day"
    end

    create_rollup_view(conn)
  end

  def create_rollup_view(conn)
    return if conn.data_source_exists?(ROLLUP_VIEW)

    quoted_view = conn.quote_table_name(ROLLUP_VIEW)
    quoted_source = conn.quote_table_name(COUNTS_TABLE)
    conn.execute(<<~SQL.squish)
      CREATE VIEW #{quoted_view} AS
      SELECT
        day AS metric_date,
        method_name,
        subject_name,
        SUM(call_count)::bigint AS call_count,
        SUM(CASE WHEN failed THEN call_count ELSE 0 END)::bigint AS failed_count,
        SUM(CASE WHEN rate_limited THEN call_count ELSE 0 END)::bigint AS rate_limited_count
      FROM #{quoted_source}
      GROUP BY day, method_name, subject_name
    SQL
  end

  def drop_summary_tables(conn)
    conn.execute("DROP VIEW IF EXISTS #{conn.quote_table_name(ROLLUP_VIEW)}")
    conn.drop_table COUNTS_TABLE if conn.data_source_exists?(COUNTS_TABLE)
  end
end
