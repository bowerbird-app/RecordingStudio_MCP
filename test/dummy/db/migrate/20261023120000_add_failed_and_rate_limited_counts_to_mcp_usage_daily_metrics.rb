# frozen_string_literal: true

class AddFailedAndRateLimitedCountsToMcpUsageDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    add_integer_count :failed_count
    add_integer_count :rate_limited_count
  end

  def add_integer_count(column)
    add_column :recording_studio_mcp_usage_daily_metrics, column, :integer,
               null: false, default: 0, if_not_exists: true
  end
end
