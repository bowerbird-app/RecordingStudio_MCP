# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module UsageWindow
    module_function

    def series
      [{ name: "Calls", data: week_points }]
    end

    def total
      counts.values.sum
    end

    def logs
      return UsageLog.none unless logs_ready?

      UsageLog.all
    end

    def screen_path(context)
      context&.admin_screen_path("mcp_usage")
    end

    def week_points
      totals = counts_by_day
      week_slices.map { |slice| { x: slice.first.strftime("%b %-d"), y: slice.sum { |day| totals.fetch(day, 0) } } }
    end

    def week_slices
      remaining = days.dup
      slices = Array.new(4) { remaining.pop(7) }.reverse
      slices[0] = remaining + slices[0]
      slices
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
    private_class_method :week_points, :week_slices, :counts_by_day, :counts, :days, :day_range, :metrics_ready?,
                         :logs_ready?
  end
end
