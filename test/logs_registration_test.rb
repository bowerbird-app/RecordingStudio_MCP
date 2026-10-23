# frozen_string_literal: true

require "test_helper"

class LogsRegistrationTest < Minitest::Test
  def test_register_unpartitioned_usage_log_with_daily_aggregation
    RecordingStudioMcp::LogsRegistration.register!

    log = RecordingStudioLogs.registry.log_for(RecordingStudioMcp::LogsRegistration::SOURCE_MODEL)
    refute_nil log
    assert_nil log.partition_interval
    assert_equal :occurred_at, log.timestamp_column
    assert_equal 30.days, log.declared_retention
    assert_nil log.root_column

    aggregations = RecordingStudioLogs.registry.aggregations_for(log)
    assert_equal 1, aggregations.size
    aggregation = aggregations.first
    assert_equal RecordingStudioMcp::LogsRegistration::AGGREGATION_NAME, aggregation.name
    assert_equal :metric_date, aggregation.period_column
    assert_equal %i[method_name subject_name], aggregation.group_by
    assert_equal %i[call_count failed_count rate_limited_count], aggregation.measurements.map(&:name)
    assert_equal %i[sum sum], aggregation.measurements.drop(1).map(&:operation)
    assert_equal %i[failed_count rate_limited_count], aggregation.measurements.drop(1).map(&:column)
  end

  def test_does_not_ship_a_nightly_usage_rake_task
    refute File.exist?(File.expand_path("../lib/tasks/recording_studio_mcp_usage.rake", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_mcp/aggregate_usage.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_mcp/maintain_usage.rb", __dir__))
    refute File.exist?(File.expand_path("../app/jobs/recording_studio_mcp/maintain_usage_job.rb", __dir__))
  end

  def test_registers_usage_counts_on_the_existing_daily_metric_table
    source = File.read(File.expand_path("../lib/recording_studio_mcp/logs_registration.rb", __dir__))

    assert_includes source, "RecordingStudioLogs.aggregate"
    assert_includes source, "UsageDailyMetric"
    assert_includes source, "period_column: :metric_date"
    refute File.exist?(File.expand_path("../app/models/recording_studio_mcp/usage_day_summary.rb", __dir__))
    refute File.exist?(File.expand_path("../app/models/recording_studio_mcp/usage_day_metric_rollup.rb", __dir__))
  end
end
