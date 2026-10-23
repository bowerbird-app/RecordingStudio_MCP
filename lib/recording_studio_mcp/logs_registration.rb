# frozen_string_literal: true

module RecordingStudioMcp
  module LogsRegistration
    SOURCE_MODEL = "RecordingStudioMcp::UsageLog"
    SUMMARY_MODEL = "RecordingStudioMcp::UsageDailyMetric"
    AGGREGATION_NAME = "mcp/usage_daily"
    OWNER = "RecordingStudioMcp"
    LOG_RETENTION = 30.days
    USAGE_MEASUREMENTS = {
      call_count: :count,
      failed_count: { sum: :failed_count },
      rate_limited_count: { sum: :rate_limited_count }
    }.freeze
    AGGREGATION = {
      source: SOURCE_MODEL,
      name: AGGREGATION_NAME,
      summary_model: SUMMARY_MODEL,
      owner: OWNER,
      period: :day,
      period_column: :metric_date,
      group_by: %i[method_name subject_name],
      measurements: USAGE_MEASUREMENTS,
      include_current: true,
      count: :sync
    }.freeze
    FILTER_GROUP = { filter: [:eq], group: true }.freeze
    SUM_MEASUREMENT = { measurements: [:sum] }.freeze
    AGGREGATABLE = {
      api_client_id: FILTER_GROUP,
      method_name: FILTER_GROUP,
      subject_name: FILTER_GROUP,
      status_code: FILTER_GROUP,
      failed: FILTER_GROUP,
      rate_limited: FILTER_GROUP,
      failed_count: SUM_MEASUREMENT,
      rate_limited_count: SUM_MEASUREMENT,
      duration_ms: { measurements: %i[sum maximum] }
    }.freeze

    module_function

    def register!
      return unless defined?(RecordingStudioLogs)

      register_log!
      register_aggregation!
      RecordingStudioLogs.finalize!
    end

    def register_log!
      RecordingStudioLogs.register(
        model: SOURCE_MODEL,
        timestamp_column: :occurred_at,
        partition_interval: nil,
        owner: OWNER,
        retention: LOG_RETENTION,
        aggregatable: AGGREGATABLE
      )
    end

    def register_aggregation!
      RecordingStudioLogs.aggregate(**AGGREGATION)
    end
  end
end
