# frozen_string_literal: true

module RecordingStudioMcp
  class AggregateUsage
    def self.call(metric_date:)
      new(metric_date: metric_date).call
    end

    def initialize(metric_date:)
      @metric_date = metric_date.to_date
    end

    def call
      return false unless tables_ready?

      replace_day(grouped_logs)
      true
    end

    private

    attr_reader :metric_date

    def tables_ready?
      UsageLog.table_available? && UsageDailyMetric.table_available?
    end

    def replace_day(grouped)
      UsageDailyMetric.transaction do
        UsageDailyMetric.where(metric_date: metric_date).delete_all
        grouped.each { |row| create_metric(row) }
      end
    end

    def create_metric(row)
      method_name, subject_name, call_count, failed_count, rate_limited_count = row
      UsageDailyMetric.create!(
        metric_date: metric_date,
        method_name: method_name,
        subject_name: subject_name.to_s,
        call_count: call_count.to_i,
        failed_count: failed_count.to_i,
        rate_limited_count: rate_limited_count.to_i
      )
    end

    def grouped_logs
      range = metric_date.in_time_zone.beginning_of_day..metric_date.in_time_zone.end_of_day
      UsageLog.where(occurred_at: range).group(:method_name, :subject_name).pluck(
        :method_name,
        :subject_name,
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(CASE WHEN failed THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN rate_limited THEN 1 ELSE 0 END)")
      )
    end
  end
end
