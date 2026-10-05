# frozen_string_literal: true

module RecordingStudioMcp
  module Notifier
    module_function

    def recording_saved(event)
      return unless RecordingStudioMcp.event_registered?(Events::RECORDING_UPDATED)

      recording = recording_from(event)
      return if recording.nil?

      notify(uri: Resources.uri_for(recording), recording: recording)
    end

    def notify(uri:, recording: nil)
      Connections.each do |connection|
        next unless connection.subscribed?(uri)
        next unless still_accessible?(connection, uri, recording)

        connection.notify_updated(uri)
      end
    end

    def recording_from(event)
      return event.recording if event.respond_to?(:recording) && event.recording
      return unless event.respond_to?(:recording_id) && event.recording_id
      return unless defined?(RecordingStudio::Recording)

      RecordingStudio::Recording.find_by(id: event.recording_id)
    end
    private_class_method :recording_from

    def still_accessible?(connection, uri, recording)
      return Resources.accessible?(connection.access_grant, uri) if recording.nil?

      scope = Resources.accessible_scope(connection.access_grant)
      return false if scope.nil?

      scope.exists?(id: recording.id)
    end
    private_class_method :still_accessible?
  end
end
