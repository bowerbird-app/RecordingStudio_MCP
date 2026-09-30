# frozen_string_literal: true

module RecordingStudioMcp
  class UsageRecorder
    class << self
      attr_writer :sink

      def record!(usage_call)
        payload = usage_call.attributes
        sink.call(payload)
        payload
      rescue StandardError => e
        warn_failure(e)
        nil
      end

      def sink
        @sink ||= ->(payload) { UsageLog.record_payload!(payload) }
      end

      private

      def warn_failure(error)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.warn("[RecordingStudioMcp] usage log failed: #{error.class}: #{error.message}")
      end
    end
  end
end
