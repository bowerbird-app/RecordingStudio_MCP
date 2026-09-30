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

  def test_usage_widget_lists_calls_failures_and_the_busiest_subjects
    install_widget_metrics

    items = RecordingStudioMcp::Admin.usage_items

    assert_equal({ leading: "Calls", text: "21" }, items[0])
    assert_equal({ leading: "Failed", text: "2" }, items[1])
    names = items.drop(2).map { |item| item.fetch(:text) }
    counts = items.drop(2).map { |item| item.fetch(:trailing) }
    assert_equal %w[list show describe create update], names
    assert_equal %w[6 5 4 3 2], counts
  end

  def test_usage_widget_says_none_yet_when_there_are_no_calls
    install_widget_metrics(calls: 0, failed: 0, subjects: {})

    assert_equal [{ text: "None yet" }], RecordingStudioMcp::Admin.usage_items
  end

  def test_usage_widget_says_none_yet_when_metrics_cannot_be_read
    metric = Class.new do
      def self.table_available?
        raise "nope"
      end
    end
    install_constant(:UsageDailyMetric, metric)

    assert_equal [{ text: "None yet" }], RecordingStudioMcp::Admin.usage_items
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

  def install_widget_metrics(calls: 21, failed: 2, subjects: nil)
    subjects ||= { "list" => 6, "show" => 5, "describe" => 4, "create" => 3, "update" => 2, "ping" => 1 }
    metric = Class.new do
      class << self
        attr_accessor :calls, :failed, :subjects
      end

      def self.table_available?
        true
      end

      def self.where(metric_date:)
        Scope.new(metric_date, calls, failed, subjects)
      end
    end
    metric.calls = calls
    metric.failed = failed
    metric.subjects = subjects
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
    def initialize(metric_date, calls, failed, subjects)
      raise "expected the last 7 days" unless metric_date.begin == Date.current - 6 && metric_date.end == Date.current

      @calls = calls
      @failed = failed
      @subjects = subjects
    end

    def sum(column)
      column == :failed_count ? @failed : @calls
    end

    def where
      Narrow.new(@subjects)
    end
  end

  class Narrow
    def initialize(subjects)
      @subjects = subjects
    end

    def not(subject_name:)
      raise "expected blank subjects to be skipped" unless subject_name == ""

      self
    end

    def group(*)
      self
    end

    def sum(*)
      @subjects
    end
  end
end
