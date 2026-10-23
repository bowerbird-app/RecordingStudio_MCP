# frozen_string_literal: true

class AddFailedAndRateLimitedCountsToMcpUsageDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    add_integer_count :recording_studio_mcp_usage_daily_metrics, :failed_count
    add_integer_count :recording_studio_mcp_usage_daily_metrics, :rate_limited_count
    add_integer_count :recording_studio_mcp_usage_logs, :failed_count
    add_integer_count :recording_studio_mcp_usage_logs, :rate_limited_count
    reversible { |direction| direction.up { backfill_log_counts } }
  end

  def add_integer_count(table, column)
    add_column table, column, :integer, null: false, default: 0, if_not_exists: true
  end

  def backfill_log_counts
    execute <<~SQL.squish
      UPDATE recording_studio_mcp_usage_logs
      SET failed_count = CASE WHEN failed THEN 1 ELSE 0 END,
          rate_limited_count = CASE WHEN rate_limited THEN 1 ELSE 0 END
    SQL
  end
end
