# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module UsageWindow
    module_function

    def series
      [{ name: "Calls", data: points }]
    end

    def total
      counts.values.sum
    end

    def logs
      return UsageLog.none unless logs_ready?

      UsageLog.all
    end

    def screen_path(context)
      return unless context

      "#{context.admin_screen_path('mcp_usage')}?#{screen_query.to_query}"
    end

    def points
      totals = counts_by_day
      days.map { |day| { x: day.strftime("%b %-d"), y: totals.fetch(day, 0) } }
    end

    def counts_by_day
      counts.transform_keys(&:to_date)
    end

    def counts
      return {} unless metrics_ready?

      UsageDailyMetric.where(metric_date: day_range).group(:metric_date).sum(:call_count)
    rescue StandardError
      {}
    end

    def days
      day_range.to_a
    end

    def day_range
      period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
      period.start_date..period.end_date
    end

    def screen_query
      range = day_range
      { start_date: range.begin.iso8601, end_date: range.end.iso8601, group_by: "day" }
    end

    def metrics_ready?
      UsageDailyMetric.table_available?
    rescue StandardError
      false
    end

    def logs_ready?
      UsageLog.table_available?
    rescue StandardError
      false
    end
    private_class_method :points, :counts_by_day, :counts, :days, :day_range, :screen_query, :metrics_ready?,
                         :logs_ready?
  end
end
