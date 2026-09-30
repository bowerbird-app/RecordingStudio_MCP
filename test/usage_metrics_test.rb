# frozen_string_literal: true

require "test_helper"

class UsageMetricsTest < Minitest::Test
  def teardown
    remove_constant(:UsageLog)
    remove_constant(:UsageDailyMetric)
  end

  def test_maintain_usage_rebuilds_two_days_and_prunes_old_logs
    today = Date.new(2026, 9, 30)
    install_logs(rows: [["tools/call", "list", 2, 1, 0]], pruned: 4, today: today)
    install_metrics

    result = RecordingStudioMcp::MaintainUsage.call(today: today)

    assert_equal [today - 1, today], result.fetch(:aggregated_dates)
    assert_equal 4, result.fetch(:pruned_logs)
    assert_equal 2, RecordingStudioMcp::UsageDailyMetric.created.size
    created = RecordingStudioMcp::UsageDailyMetric.created.first
    assert_equal today - 1, created.fetch(:metric_date)
    assert_equal "tools/call", created.fetch(:method_name)
    assert_equal "list", created.fetch(:subject_name)
    assert_equal 2, created.fetch(:call_count)
    assert_equal 1, created.fetch(:failed_count)
    assert_equal 0, created.fetch(:rate_limited_count)
    assert_equal [today - 1, today], RecordingStudioMcp::UsageDailyMetric.cleared_dates
  end

  def test_maintain_usage_does_nothing_without_the_log_table
    install_logs(available: false)

    result = RecordingStudioMcp::MaintainUsage.call(today: Date.new(2026, 9, 30))

    assert_equal({ aggregated_dates: [], pruned_logs: 0 }, result)
  end

  def test_aggregate_usage_replaces_an_empty_day
    install_logs(rows: [])
    install_metrics

    assert_equal true, RecordingStudioMcp::AggregateUsage.call(metric_date: Date.new(2026, 9, 30))
    assert_equal [Date.new(2026, 9, 30)], RecordingStudioMcp::UsageDailyMetric.cleared_dates
    assert_empty RecordingStudioMcp::UsageDailyMetric.created
  end

  def test_aggregate_usage_does_nothing_without_both_tables
    install_logs(rows: [])
    install_metrics(available: false)

    assert_equal false, RecordingStudioMcp::AggregateUsage.call(metric_date: Date.new(2026, 9, 30))
    assert_empty RecordingStudioMcp::UsageDailyMetric.cleared_dates
  end

  def test_usage_window_totals_calls_across_the_last_four_weeks
    install_widget_metrics

    assert_equal 15, RecordingStudioMcp::UsageWindow.total
    points = RecordingStudioMcp::UsageWindow.series.first.fetch(:data)
    period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
    assert_equal (period.start_date..period.end_date).to_a.size, points.size
    assert_equal period.start_date..period.end_date, RecordingStudioMcp::UsageDailyMetric.seen_range
    today = points.find { |point| point.fetch(:x) == Date.current.strftime("%b %-d") }
    assert_equal 6, today.fetch(:y)
    assert_equal 0, points.first.fetch(:y)
  end

  def test_usage_window_is_zero_when_there_are_no_calls
    install_widget_metrics(counts: {})

    assert_equal 0, RecordingStudioMcp::UsageWindow.total
    points = RecordingStudioMcp::UsageWindow.series.first.fetch(:data)
    zeros = points.all? { |point| point.fetch(:y).zero? }
    assert zeros
  end

  def test_usage_window_is_zero_when_metrics_cannot_be_read
    metric = Class.new do
      def self.table_available?
        raise "nope"
      end
    end
    install_constant(:UsageDailyMetric, metric)

    assert_equal 0, RecordingStudioMcp::UsageWindow.total
    points = RecordingStudioMcp::UsageWindow.series.first.fetch(:data)
    zeros = points.all? { |point| point.fetch(:y).zero? }
    assert zeros
    refute_empty points
  end

  private

  def install_logs(rows: [], pruned: 0, available: true, today: Date.new(2026, 9, 30))
    log = Class.new do
      class << self
        attr_accessor :rows, :pruned, :today
      end

      def self.table_available?
        @available
      end

      def self.where(occurred_at:)
        Query.new(occurred_at, rows, pruned, today)
      end
    end
    log.rows = rows
    log.pruned = pruned
    log.today = today
    log.instance_variable_set(:@available, available)
    install_constant(:UsageLog, log)
  end

  def install_metrics(available: true)
    metric = Class.new do
      class << self
        attr_accessor :created, :cleared_dates, :available
      end

      def self.table_available?
        available
      end

      def self.transaction
        yield
      end

      def self.where(metric_date:)
        Day.new(metric_date, self)
      end

      def self.create!(attributes)
        created << attributes
      end
    end
    metric.created = []
    metric.cleared_dates = []
    metric.available = available
    install_constant(:UsageDailyMetric, metric)
  end

  def install_widget_metrics(counts: nil)
    counts ||= { Date.current => 6, Date.current - 1 => 5, Date.current - 3 => 4 }
    metric = Class.new do
      class << self
        attr_accessor :counts, :seen_range
      end

      def self.table_available?
        true
      end

      def self.where(metric_date:)
        self.seen_range = metric_date
        Scope.new(counts)
      end
    end
    metric.counts = counts
    metric.seen_range = nil
    install_constant(:UsageDailyMetric, metric)
  end

  def install_constant(name, value)
    remove_constant(name)
    RecordingStudioMcp.const_set(name, value)
  end

  def remove_constant(name)
    RecordingStudioMcp.send(:remove_const, name) if RecordingStudioMcp.const_defined?(name, false)
  end

  class Query
    def initialize(occurred_at, rows, pruned, today)
      @occurred_at = occurred_at
      @rows = rows
      @pruned = pruned
      @today = today
    end

    def group(*)
      self
    end

    def pluck(*)
      range = @occurred_at
      raise "expected a day range" unless range.begin && range.end

      @rows
    end

    def delete_all
      cutoff = @today.in_time_zone.beginning_of_day - RecordingStudioMcp::MaintainUsage::LOG_RETENTION_DAYS.days
      raise "expected the retention cutoff" unless @occurred_at.end == cutoff

      @pruned
    end
  end

  class Day
    def initialize(metric_date, metric)
      @metric_date = metric_date
      @metric = metric
    end

    def delete_all
      @metric.cleared_dates << @metric_date
    end
  end

  class Scope
    def initialize(counts)
      @counts = counts
    end

    def group(*)
      self
    end

    def sum(*)
      @counts
    end
  end
end
