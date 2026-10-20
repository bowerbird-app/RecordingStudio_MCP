# frozen_string_literal: true

module RecordingStudioMcp
  module LogsRegistration
    SOURCE_MODEL = "RecordingStudioMcp::UsageLog"
    USAGE_COUNTS = "mcp/usage_counts"
    OWNER = "RecordingStudioMcp"

    module_function

    def summaries_enabled?
      RecordingStudioMcp.configuration.logs_summaries_enabled
    end

    def logging_connection
      UsageLog.connection
    end

    def resolved_retention
      MaintainUsage::LOG_RETENTION_DAYS.days
    end

    def register!
      return unless defined?(RecordingStudioLogs)

      register_log!
      register_usage_counts!
      RecordingStudioLogs.finalize!
    end

    def register_log!
      RecordingStudioLogs.register(
        model: SOURCE_MODEL,
        timestamp_column: :occurred_at,
        partition_interval: nil,
        owner: OWNER,
        retention: resolved_retention,
        aggregatable: aggregatable_columns
      )
    end

    def register_usage_counts!
      RecordingStudioLogs.aggregate(
        source: SOURCE_MODEL,
        name: USAGE_COUNTS,
        summary_model: "RecordingStudioMcp::UsageDaySummary",
        owner: OWNER,
        group_by: %i[method_name subject_name failed rate_limited],
        measurements: { call_count: :count }
      )
    end

    def aggregatable_columns
      {
        api_client_id: { filter: [:eq], group: true },
        method_name: { filter: [:eq], group: true },
        subject_name: { filter: [:eq], group: true },
        status_code: { filter: [:eq], group: true },
        failed: { filter: [:eq], group: true },
        rate_limited: { filter: [:eq], group: true },
        duration_ms: { measurements: %i[sum maximum] }
      }
    end

    def usage_counts_definition
      RecordingStudioLogs.registry.aggregation(USAGE_COUNTS)
    end
  end
end
