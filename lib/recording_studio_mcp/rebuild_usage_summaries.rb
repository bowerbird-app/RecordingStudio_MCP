# frozen_string_literal: true

module RecordingStudioMcp
  class RebuildUsageSummaries
    class << self
      def call(day:)
        new(day: day).call
      end

      def lookback!(lookback_days:)
        today = Time.now.utc.to_date
        dates = []
        Integer(lookback_days).downto(1) do |days_ago|
          date = today - days_ago
          call(day: date)
          dates << date
        end
        dates
      end

      def backfill!(from:, to:)
        date = from.to_date
        finish = to.to_date
        while date <= finish
          call(day: date)
          date += 1
        end
      end
    end

    def initialize(day:)
      @day = day.to_date
    end

    def call
      LogsRegistration.register!
      connection = LogsRegistration.logging_connection
      RecordingStudioLogs::Aggregation::Runner.call(
        LogsRegistration.usage_counts_definition,
        day: day,
        connection: connection
      )
      day
    end

    private

    attr_reader :day
  end
end
