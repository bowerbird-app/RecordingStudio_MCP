# frozen_string_literal: true

class CreateRecordingStudioMcpUsageSummaries < ActiveRecord::Migration[8.1]
  COUNTS_TABLE = "recording_studio_mcp_usage_day_summaries"
  ROLLUP_VIEW = "recording_studio_mcp_usage_day_metric_rollups"

  def up
    RecordingStudioLogs::Schema.install_runs!(connection)
    create_summary_table
    create_rollup_view
  end

  def down
    execute("DROP VIEW IF EXISTS #{connection.quote_table_name(ROLLUP_VIEW)}")
    drop_table COUNTS_TABLE if table_exists?(COUNTS_TABLE)
  end

  private

  def create_summary_table
    return if table_exists?(COUNTS_TABLE)

    create_table COUNTS_TABLE, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
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
      name: "index_rs_mcp_usage_day_summaries_identity"
    )
    add_index COUNTS_TABLE, :day, name: "index_rs_mcp_usage_day_summaries_on_day"
  end

  def create_rollup_view
    return if connection.data_source_exists?(ROLLUP_VIEW)

    quoted_view = connection.quote_table_name(ROLLUP_VIEW)
    quoted_source = connection.quote_table_name(COUNTS_TABLE)
    execute(<<~SQL.squish)
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
end
