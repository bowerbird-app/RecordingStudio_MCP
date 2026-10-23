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
      failed_count: { sum: :failed },
      rate_limited_count: { sum: :rate_limited }
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
        aggregatable: aggregatable_columns
      )
    end

    def register_aggregation!
      RecordingStudioLogs.aggregate(**AGGREGATION)
    end

    def aggregatable_columns
      {
        api_client_id: { filter: [:eq], group: true },
        method_name: { filter: [:eq], group: true },
        subject_name: { filter: [:eq], group: true },
        status_code: { filter: [:eq], group: true },
        failed: { filter: [:eq], group: true, measurements: [:sum] },
        rate_limited: { filter: [:eq], group: true, measurements: [:sum] },
        duration_ms: { measurements: %i[sum maximum] }
      }
    end
  end
end
