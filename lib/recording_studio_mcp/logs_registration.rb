# frozen_string_literal: true

module RecordingStudioMcp
  module LogsRegistration
    SOURCE_MODEL = "RecordingStudioMcp::UsageLog"
    OWNER = "RecordingStudioMcp"

    module_function

    def register!
      return unless defined?(RecordingStudioLogs)

      register_log!
      RecordingStudioLogs.finalize!
    end

    def register_log!
      RecordingStudioLogs.register(
        model: SOURCE_MODEL,
        timestamp_column: :occurred_at,
        partition_interval: nil,
        owner: OWNER,
        retention: :indefinite,
        aggregatable: aggregatable_columns
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
  end
end
