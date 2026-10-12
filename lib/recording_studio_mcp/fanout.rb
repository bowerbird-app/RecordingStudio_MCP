# frozen_string_literal: true

module RecordingStudioMcp
  module Fanout
    # Postgres rejects NOTIFY payloads of 8000 bytes or more.
    NOTIFY_PAYLOAD_MAX_BYTES = 8000

    module_function

    def publish(event_name:, recording_id:, recording: nil)
      WebhookDispatch.enqueue(event_name: event_name, recording_id: recording_id, recording: recording)
      if PostgresBus.enabled?
        # NOTIFY from any Postgres process (web, bin/jobs, rake, runner) so web
        # LISTENers get the update. LISTEN is gated separately in start_allowed?.
        # On failure or oversize payload, fall back to local deliver — never raise
        # into record! / the caller's transaction.
        notified = notify_bus(event_name: event_name, recording_id: recording_id)
        # A listening process receives its own NOTIFY on the listen connection —
        # skip in-process deliver to avoid double delivery.
        return if notified && PostgresBus.listening?
      end

      Notifier.deliver_local(event_name: event_name, recording_id: recording_id, recording: recording)
    end

    def notify_bus(event_name:, recording_id:)
      payload = PostgresBus.notify_payload(event_name: event_name, recording_id: recording_id)
      return false if oversize_payload?(payload)

      PostgresBus.publish_payload(payload)
      true
    rescue *notify_recoverable_errors => e
      log_warn("NOTIFY failed (#{e.class}: #{e.message}); delivering locally")
      false
    end
    private_class_method :notify_bus

    def oversize_payload?(payload)
      return false if payload.bytesize < NOTIFY_PAYLOAD_MAX_BYTES

      log_warn(
        "NOTIFY payload #{payload.bytesize} bytes exceeds " \
        "#{NOTIFY_PAYLOAD_MAX_BYTES}; delivering locally"
      )
      true
    end
    private_class_method :oversize_payload?

    def notify_recoverable_errors
      errors = [IOError]
      errors << ActiveRecord::ActiveRecordError if defined?(ActiveRecord::ActiveRecordError)
      errors << PG::Error if defined?(PG::Error)
      errors
    end
    private_class_method :notify_recoverable_errors

    def log_warn(message)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[RecordingStudioMcp::Fanout] #{message}")
    end
    private_class_method :log_warn
  end
end
