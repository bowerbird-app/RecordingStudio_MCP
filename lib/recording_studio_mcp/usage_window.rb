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

    def failed_calls_path(context)
      path = screen_path(context)
      return path if path.blank?

      query = { failed: "true", method: "tools/call" }.to_query
      "#{path}?#{query}"
    end

    def week_points
      totals = counts_by_day
      missing = LogsRegistration.summaries_enabled? ? nil : 0
      week_slices.map do |slice|
        {
          x: slice.first.strftime("%b %-d"),
          y: slice.sum { |day| totals.fetch(day, missing).to_i }
        }
      end
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
      return coverage_counts if LogsRegistration.summaries_enabled?

      UsageDailyMetric.where(metric_date: day_range).group(:metric_date).sum(:call_count)
    rescue StandardError
      {}
    end

    def coverage_counts
      coverage = UsageCoverage.new
      day_range.each_with_object({}) do |day, hash|
        kind = coverage.source_for(day).kind
        next if kind == :gap

        hash[day] = count_for(day, kind)
      end
    end

    def count_for(day, kind)
      case kind
      when :summary then summary_count(day)
      when :raw then raw_count(day)
      else legacy_count(day)
      end
    end

    def summary_count(day)
      return 0 unless UsageDayMetricRollup.table_available?

      UsageDayMetricRollup.where(metric_date: day).sum(:call_count)
    end

    def raw_count(day)
      start_at, finish_at = UsageCoverage.new.utc_window(day)
      UsageLog.where(occurred_at: start_at...finish_at).count
    end

    def legacy_count(day)
      UsageDailyMetric.where(metric_date: day).sum(:call_count)
    end

    def days
      day_range.to_a
    end

    def day_range
      period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
      period.start_date..period.end_date
    end

    def metrics_ready?
      if LogsRegistration.summaries_enabled?
        UsageDayMetricRollup.table_available? || UsageLog.table_available? || UsageDailyMetric.table_available?
      else
        UsageDailyMetric.table_available?
      end
    rescue StandardError
      false
    end

    def logs_ready?
      UsageLog.table_available?
    rescue StandardError
      false
    end
    private_class_method :week_points, :week_slices, :counts_by_day, :counts, :coverage_counts, :count_for,
                         :summary_count, :raw_count, :legacy_count, :days, :day_range, :metrics_ready?,
                         :logs_ready?
  end
end
