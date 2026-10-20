# frozen_string_literal: true

require "test_helper"

class LogsRegistrationTest < Minitest::Test
  def setup
    RecordingStudioMcp.configuration.logs_summaries_enabled = false
  end

  def teardown
    RecordingStudioMcp.configuration.logs_summaries_enabled = false
  end

  def test_summaries_default_off
    assert_equal false, RecordingStudioMcp::LogsRegistration.summaries_enabled?
  end

  def test_register_unpartitioned_usage_counts
    RecordingStudioMcp::LogsRegistration.register!

    log = RecordingStudioLogs.registry.log_for(RecordingStudioMcp::LogsRegistration::SOURCE_MODEL)
    refute_nil log
    assert_nil log.partition_interval
    assert_equal :occurred_at, log.timestamp_column
    assert_equal RecordingStudioMcp::MaintainUsage::LOG_RETENTION_DAYS.days, log.declared_retention

    aggregation = RecordingStudioMcp::LogsRegistration.usage_counts_definition
    refute_nil aggregation
    assert_equal "mcp/usage_counts", aggregation.name
    assert_equal %i[method_name subject_name failed rate_limited], aggregation.group_by
  end

  def test_rake_task_backfills_summaries
    rake = File.read(File.expand_path("../lib/tasks/recording_studio_mcp_usage.rake", __dir__))

    assert_includes rake, "namespace :usage_logs"
    assert_includes rake, "task backfill_summaries"
    assert_includes rake, "RebuildUsageSummaries.backfill!"
    assert_includes rake, 'ENV.fetch("FROM")'
    assert_includes rake, 'ENV.fetch("TO")'
  end
end
