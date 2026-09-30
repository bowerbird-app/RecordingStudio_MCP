# frozen_string_literal: true

module RecordingStudioMcp
  class MaintainUsage
    LOG_RETENTION_DAYS = 30

    def self.call(today: Date.current)
      new(today: today).call
    end

    def initialize(today:)
      @today = today.to_date
    end

    def call
      return { aggregated_dates: [], pruned_logs: 0 } unless UsageLog.table_available?

      dates.each { |date| AggregateUsage.call(metric_date: date) }
      { aggregated_dates: dates, pruned_logs: prune_old_logs }
    end

    private

    attr_reader :today

    def dates
      [today - 1, today]
    end

    def prune_old_logs
      cutoff = today.in_time_zone.beginning_of_day - LOG_RETENTION_DAYS.days
      UsageLog.where(occurred_at: ...cutoff).delete_all
    end
  end
end
