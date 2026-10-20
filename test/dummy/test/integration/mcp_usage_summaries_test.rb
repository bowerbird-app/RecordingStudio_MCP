# frozen_string_literal: true

require "test_helper"

class McpUsageSummariesTest < ActiveSupport::TestCase
  setup do
    RecordingStudioMcp.configuration.logs_summaries_enabled = true
    RecordingStudioMcp::LogsRegistration.register!
    RecordingStudioMcp::UsageLog.delete_all
    RecordingStudioMcp::UsageDailyMetric.delete_all
    RecordingStudioMcp::UsageDaySummary.delete_all if RecordingStudioMcp::UsageDaySummary.table_available?
    clear_runs!
    @day = Date.new(2026, 10, 1)
  end

  teardown do
    RecordingStudioMcp.configuration.logs_summaries_enabled = false
  end

  test "registers unpartitioned summaries and keeps the raw uuid primary key" do
    connection = RecordingStudioMcp::UsageLog.connection
    %w[
      recording_studio_mcp_usage_logs
      recording_studio_mcp_usage_day_summaries
    ].each do |table|
      relkind = connection.select_value("SELECT relkind FROM pg_class WHERE relname = #{connection.quote(table)}")
      assert_equal "r", relkind, table
    end
    assert_equal "id", connection.primary_key("recording_studio_mcp_usage_logs")
    type = connection.select_value(<<~SQL.squish)
      SELECT data_type FROM information_schema.columns
      WHERE table_name = 'recording_studio_mcp_usage_logs' AND column_name = 'id'
    SQL
    assert_equal "uuid", type
    assert RecordingStudioMcp::UsageDayMetricRollup.table_available?
  end

  test "rebuilds usage counts and is idempotent" do
    insert_log(method_name: "tools/call", subject_name: "list", failed: false, rate_limited: false)
    insert_log(method_name: "tools/call", subject_name: "list", failed: true, rate_limited: false)
    insert_log(method_name: "ping", subject_name: "", failed: false, rate_limited: true)

    RecordingStudioMcp::RebuildUsageSummaries.call(day: @day)

    counts = RecordingStudioMcp::UsageDaySummary.where(day: @day)
    assert_equal 3, counts.sum(:call_count)
    assert_equal 2, counts.where(method_name: "tools/call", subject_name: "list").sum(:call_count)
    assert_equal 1, counts.where(failed: true).sum(:call_count)
    assert_equal 1, counts.where(rate_limited: true).sum(:call_count)

    rollup = RecordingStudioMcp::UsageDayMetricRollup.where(metric_date: @day)
    list = rollup.find_by!(method_name: "tools/call", subject_name: "list")
    assert_equal 2, list.call_count
    assert_equal 1, list.failed_count
    assert_equal 0, list.rate_limited_count

    first_id = RecordingStudioMcp::UsageDaySummary.find_by!(day: @day, method_name: "ping").id
    RecordingStudioMcp::RebuildUsageSummaries.call(day: @day)
    assert_equal 3, RecordingStudioMcp::UsageDaySummary.where(day: @day).sum(:call_count)
    refute_equal first_id, RecordingStudioMcp::UsageDaySummary.find_by!(day: @day, method_name: "ping").id
  end

  test "legacy aggregate and live increment skip when summaries are enabled" do
    insert_log(method_name: "ping", subject_name: "", failed: false, rate_limited: false)
    refute RecordingStudioMcp::AggregateUsage.call(metric_date: @day)
    assert_equal 0, RecordingStudioMcp::UsageDailyMetric.where(metric_date: @day).count

    RecordingStudioMcp::UsageLog.record_payload!(
      method_name: "initialize",
      subject_name: "",
      status_code: 200,
      duration_ms: 4,
      rate_limited: false,
      failed: false,
      api_client_id: nil
    )
    assert_equal 0, RecordingStudioMcp::UsageDailyMetric.count
  end

  test "coverage mixes summary, raw, legacy, and omits gaps" do
    insert_log(method_name: "ping", subject_name: "", failed: false, rate_limited: false)
    RecordingStudioMcp::RebuildUsageSummaries.call(day: @day)

    raw_day = Date.new(2026, 10, 2)
    insert_log(method_name: "ping", subject_name: "", failed: false, rate_limited: false, occurred_at: Time.utc(2026, 10, 2, 12))

    legacy_day = Date.new(2026, 9, 15)
    RecordingStudioMcp::UsageDailyMetric.increment!(
      metric_date: legacy_day,
      method_name: "ping",
      subject_name: "",
      failed: false,
      rate_limited: false
    )

    coverage = RecordingStudioMcp::UsageCoverage.new
    assert_equal :summary, coverage.source_for(@day).kind
    assert_equal :raw, coverage.source_for(raw_day).kind
    assert_equal :legacy, coverage.source_for(legacy_day).kind
    assert_equal :gap, coverage.source_for(Date.new(2026, 1, 1)).kind
  end

  test "raw prune stays blocked until the aggregation covers the day" do
    occurred_at = Time.utc(2026, 9, 1, 12)
    insert_log(method_name: "ping", subject_name: "", failed: false, rate_limited: false, occurred_at: occurred_at)

    assert_equal 1, RecordingStudioMcp::UsageLog.count
    RecordingStudioMcp::GuardedUsageLogRetention.call(before: Time.utc(2026, 10, 18))
    assert_equal 1, RecordingStudioMcp::UsageLog.count

    RecordingStudioMcp::RebuildUsageSummaries.call(day: Date.new(2026, 9, 1))
    RecordingStudioMcp::GuardedUsageLogRetention.call(before: Time.utc(2026, 10, 18))
    assert_equal 0, RecordingStudioMcp::UsageLog.count
  end

  test "utc midnight is the summary day under a non-utc zone" do
    Time.use_zone("Pacific/Auckland") do
      insert_log(
        method_name: "ping",
        subject_name: "",
        failed: false,
        rate_limited: false,
        occurred_at: Time.utc(2026, 10, 1, 0, 30)
      )
      RecordingStudioMcp::RebuildUsageSummaries.call(day: @day)
      assert_equal 1, RecordingStudioMcp::UsageDaySummary.where(day: @day).sum(:call_count)
      assert_equal 0, RecordingStudioMcp::UsageDaySummary.where(day: @day - 1).sum(:call_count)
    end
  end

  private

  def insert_log(method_name:, subject_name:, failed:, rate_limited:, occurred_at: nil)
    RecordingStudioMcp::UsageLog.create!(
      occurred_at: occurred_at || Time.utc(@day.year, @day.month, @day.day, 12),
      method_name: method_name,
      subject_name: subject_name,
      status_code: failed ? 500 : 200,
      duration_ms: 12,
      rate_limited: rate_limited,
      failed: failed
    )
  end

  def clear_runs!
    connection = RecordingStudioMcp::LogsRegistration.logging_connection
    return unless connection.data_source_exists?("recording_studio_logs_aggregation_runs")

    connection.delete(
      "DELETE FROM #{connection.quote_table_name('recording_studio_logs_aggregation_runs')} " \
      "WHERE aggregation_name = #{connection.quote(RecordingStudioMcp::LogsRegistration::USAGE_COUNTS)}"
    )
  end
end
