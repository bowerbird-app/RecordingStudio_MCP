# frozen_string_literal: true

module RecordingStudioMcp
  module Fanout
    module_function

    def publish(event_name:, recording_id:, recording: nil)
      if PostgresBus.enabled? && PostgresBus.listening?
        PostgresBus.publish(event_name: event_name, recording_id: recording_id)
      else
        Notifier.deliver_local(event_name: event_name, recording_id: recording_id, recording: recording)
      end
    end
  end
end
