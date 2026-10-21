# frozen_string_literal: true

module RecordingStudioMcp
  class UsageLog < ApplicationRecord
    self.table_name = "recording_studio_mcp_usage_logs"

    def self.table_available?
      connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.record_payload!(payload)
      return unless table_available?

      occurred_at = Time.current
      transaction do
        create!(payload.merge(occurred_at: occurred_at))
        increment_daily(payload, occurred_at)
      end
    end

    def self.increment_daily(payload, occurred_at)
      UsageDailyMetric.increment!(
        metric_date: occurred_at.in_time_zone.to_date,
        method_name: payload.fetch(:method_name),
        subject_name: payload.fetch(:subject_name),
        failed: payload.fetch(:failed),
        rate_limited: payload.fetch(:rate_limited)
      )
    end
    private_class_method :increment_daily
  end
end
