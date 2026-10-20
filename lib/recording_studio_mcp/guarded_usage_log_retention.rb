# frozen_string_literal: true

module RecordingStudioMcp
  class GuardedUsageLogRetention
    class << self
      def call(before: nil)
        new(before: before).call
      end
    end

    def initialize(before:)
      @before = before
    end

    def call
      log = registered_log
      return 0 if skip?(log)

      connection = LogsRegistration.logging_connection
      covered, = fresh_days(log, connection)
      return 0 if covered.empty?

      delete_covered_days(log, connection, covered)
      covered.size
    end

    private

    attr_reader :before

    def registered_log
      return unless UsageLog.table_available?

      LogsRegistration.register!
      RecordingStudioLogs.registry.log_for(LogsRegistration::SOURCE_MODEL)
    end

    def skip?(log)
      log.nil? || (log.indefinite? && before.blank?)
    end

    def delete_covered_days(log, connection, covered)
      RecordingStudioLogs::Lock.with(connection, *RecordingStudioLogs::Lock.names_for(
        RecordingStudioLogs.registry.aggregations_for(log), covered
      )) do
        RecordingStudioLogs::Lock.hold_writes(connection, log.table_name)
        current, = fresh_days(log, connection)
        deletable = current & covered
        unless deletable.empty?
          RecordingStudioLogs::Retention::RawRows.delete_days(connection, log, cutoff(log), deletable)
        end
      end
    end

    def fresh_days(log, connection)
      RecordingStudioLogs::Retention::RawRows.expired_days(connection, log, cutoff(log)).partition do |day|
        day_fresh?(log, day, connection)
      end
    end

    def day_fresh?(log, day, connection)
      watermark = RecordingStudioLogs::Retention::RawRows.newest_for_days(
        connection, log, cutoff(log), [day]
      )
      RecordingStudioLogs::AggregationRun.log_fresh?(log, [day], watermark, connection: connection)
    end

    def cutoff(log)
      return before if before.present?

      Time.now.utc - log.retention
    end
  end
end
