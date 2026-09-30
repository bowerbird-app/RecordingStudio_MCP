# frozen_string_literal: true

module RecordingStudioMcp
  class UsageDailyMetric < ApplicationRecord
    self.table_name = "recording_studio_mcp_usage_daily_metrics"
    UNIQUE_INDEX = :index_rs_mcp_usage_daily_on_day_method_subject
    ADD_COUNTS = Arel.sql(<<~SQL.squish)
      call_count = recording_studio_mcp_usage_daily_metrics.call_count + EXCLUDED.call_count,
      failed_count = recording_studio_mcp_usage_daily_metrics.failed_count + EXCLUDED.failed_count,
      rate_limited_count = recording_studio_mcp_usage_daily_metrics.rate_limited_count + EXCLUDED.rate_limited_count,
      updated_at = EXCLUDED.updated_at
    SQL

    def self.table_available?
      connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.increment!(metric_date:, method_name:, subject_name:, failed:, rate_limited:)
      upsert(
        metric_row(metric_date, method_name, subject_name, failed, rate_limited),
        unique_by: UNIQUE_INDEX,
        on_duplicate: ADD_COUNTS
      )
    end

    def self.metric_row(metric_date, method_name, subject_name, failed, rate_limited)
      now = Time.current
      counts(failed, rate_limited).merge(
        metric_date: metric_date,
        method_name: method_name,
        subject_name: subject_name.to_s,
        created_at: now,
        updated_at: now
      )
    end

    def self.counts(failed, rate_limited)
      {
        call_count: 1,
        failed_count: failed ? 1 : 0,
        rate_limited_count: rate_limited ? 1 : 0
      }
    end
    private_class_method :metric_row, :counts
  end
end
