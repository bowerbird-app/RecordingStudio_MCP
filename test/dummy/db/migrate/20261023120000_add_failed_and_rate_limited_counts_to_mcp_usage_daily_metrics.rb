# frozen_string_literal: true

class AddFailedAndRateLimitedCountsToMcpUsageDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_mcp_usage_daily_metrics, :failed_count, :integer, null: false, default: 0,
                                                                                  if_not_exists: true
    add_column :recording_studio_mcp_usage_daily_metrics, :rate_limited_count, :integer, null: false, default: 0,
                                                                                        if_not_exists: true
  end
end
