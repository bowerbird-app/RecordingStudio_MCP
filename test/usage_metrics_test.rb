# frozen_string_literal: true

require "test_helper"

class UsageMetricsTest < Minitest::Test
  def setup
    skip unless RecordingStudioMcp.const_defined?(:UsageDailyMetric, false)
  end

  def test_usage_window_totals_calls_across_the_last_four_weeks
    counts = { Date.current => 6, Date.current - 1 => 5, Date.current - 3 => 4 }

    with_usage_daily_counts(counts) do
      assert_equal 15, RecordingStudioMcp::UsageWindow.total
      points = RecordingStudioMcp::UsageWindow.series.first.fetch(:data)
      period = Time.use_zone(RecordingStudioMetrics.configuration.default_timezone) do
        RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
      end
      assert_equal 4, points.size
      assert_equal 0, points.first.fetch(:y)
      assert_equal 15, points.last.fetch(:y)
      assert_equal period.end_date, Date.current
    end
  end

  def test_usage_window_is_zero_when_there_are_no_calls
    with_usage_daily_counts({}) do
      assert_equal 0, RecordingStudioMcp::UsageWindow.total
      points = RecordingStudioMcp::UsageWindow.series.first.fetch(:data)
      assert(points.all? { |point| point.fetch(:y).zero? })
    end
  end

  def test_usage_window_is_zero_when_metrics_cannot_be_read
    RecordingStudioMcp::UsageDailyMetric.stub(:table_available?, -> { raise "nope" }) do
      assert_equal 0, RecordingStudioMcp::UsageWindow.total
      points = RecordingStudioMcp::UsageWindow.series.first.fetch(:data)
      assert(points.all? { |point| point.fetch(:y).zero? })
      refute_empty points
    end
  end

  def test_record_payload_writes_a_usage_log
    skip unless RecordingStudioMcp::UsageLog.table_available?

    before_logs = RecordingStudioMcp::UsageLog.count

    RecordingStudioMcp::UsageLog.record_payload!(
      method_name: "ping",
      subject_name: "",
      status_code: 200,
      duration_ms: 1,
      failed: false,
      rate_limited: false
    )

    assert_equal before_logs + 1, RecordingStudioMcp::UsageLog.count
  end

  private

  def with_usage_daily_counts(counts, &block)
    relation = Object.new
    relation.define_singleton_method(:group) { |_| relation }
    relation.define_singleton_method(:sum) { |_| counts }

    RecordingStudioMcp::UsageDailyMetric.stub(:table_available?, true) do
      RecordingStudioMcp::UsageDailyMetric.stub(:where, ->(*) { relation }, &block)
    end
  end
end
