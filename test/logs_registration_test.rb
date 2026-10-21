# frozen_string_literal: true

require "test_helper"

class LogsRegistrationTest < Minitest::Test
  def test_register_unpartitioned_usage_log_without_aggregation
    RecordingStudioMcp::LogsRegistration.register!

    log = RecordingStudioLogs.registry.log_for(RecordingStudioMcp::LogsRegistration::SOURCE_MODEL)
    refute_nil log
    assert_nil log.partition_interval
    assert_equal :occurred_at, log.timestamp_column
    assert_equal :indefinite, log.declared_retention
    assert_nil log.root_column
    assert_empty RecordingStudioLogs.registry.aggregations_for(log)
  end

  def test_rake_task_maintains_usage_without_summary_backfill
    rake = File.read(File.expand_path("../lib/tasks/recording_studio_mcp_usage.rake", __dir__))

    assert_includes rake, "task maintain_usage"
    refute_includes rake, "namespace :usage_logs"
    refute_includes rake, "task backfill_summaries"
    refute_includes rake, "RebuildUsageSummaries"
  end

  def test_does_not_register_usage_counts_or_summary_models
    source = File.read(File.expand_path("../lib/recording_studio_mcp/logs_registration.rb", __dir__))

    refute_includes source, "register_usage_counts!"
    refute_includes source, "usage_counts_definition"
    refute_includes source, "summaries_enabled?"
    refute_includes source, "RecordingStudioLogs.aggregate"
    refute File.exist?(File.expand_path("../app/models/recording_studio_mcp/usage_day_summary.rb", __dir__))
    refute File.exist?(File.expand_path("../app/models/recording_studio_mcp/usage_day_metric_rollup.rb", __dir__))
  end
end
