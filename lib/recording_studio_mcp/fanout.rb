# frozen_string_literal: true

module RecordingStudioMcp
  module Fanout
    # Postgres rejects NOTIFY payloads of 8000 bytes or more.
    NOTIFY_PAYLOAD_MAX_BYTES = 8000

    module_function

    # Publish after the surrounding transaction commits (or immediately when
    # none is open). NOTIFY and local delivery therefore never run for
    # rolled-back changes, and a rescued NOTIFY failure cannot poison the
    # caller's transaction.
    def publish(event_name:, recording_id:, recording: nil)
      AfterCommit.run do
        deliver(event_name: event_name, recording_id: recording_id, recording: recording)
      end
    end

    def deliver(event_name:, recording_id:, recording: nil)
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
    private_class_method :deliver

    def notify_bus(event_name:, recording_id:)
      payload = PostgresBus.notify_payload(event_name: event_name, recording_id: recording_id)
      return false if oversize_payload?(payload)

      publish_notify(payload)
      true
    rescue *notify_recoverable_errors => e
      log_warn("NOTIFY failed (#{e.class}: #{e.message}); delivering locally")
      false
    end
    private_class_method :notify_bus

    # Belt-and-braces: when somehow still inside an open transaction, run NOTIFY
    # in a savepoint so a rejected statement cannot leave the host connection
    # in InFailedSqlTransaction.
    def publish_notify(payload)
      if open_transaction?
        ActiveRecord::Base.transaction(requires_new: true) do
          PostgresBus.publish_payload(payload)
        end
      else
        PostgresBus.publish_payload(payload)
      end
    end
    private_class_method :publish_notify

    def open_transaction?
      return false unless defined?(ActiveRecord::Base)
      return false unless ActiveRecord::Base.connected?

      transaction = ActiveRecord::Base.current_transaction
      transaction.respond_to?(:open?) && transaction.open?
    rescue StandardError
      false
    end
    private_class_method :open_transaction?

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
