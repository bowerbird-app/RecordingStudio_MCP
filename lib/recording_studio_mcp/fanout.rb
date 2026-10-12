# frozen_string_literal: true

module RecordingStudioMcp
  module Fanout
    module_function

    def publish(event_name:, recording_id:, recording: nil)
      WebhookDispatch.enqueue(event_name: event_name, recording_id: recording_id, recording: recording)
      if PostgresBus.enabled?
        # NOTIFY from any Postgres process (web, bin/jobs, rake, runner) so web
        # LISTENers get the update. LISTEN is gated separately in start_allowed?.
        PostgresBus.publish(event_name: event_name, recording_id: recording_id)
        # A listening process receives its own NOTIFY on the listen connection —
        # skip in-process deliver to avoid double delivery.
        return if PostgresBus.listening?
      end

      Notifier.deliver_local(event_name: event_name, recording_id: recording_id, recording: recording)
    end
  end
end
