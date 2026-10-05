# frozen_string_literal: true

module RecordingStudioMcp
  module Notifier
    module_function

    def recording_saved(event)
      recording = recording_from(event)
      return if recording.nil?

      RecordingStudioMcp.configuration.event_catalog.each do |registration|
        next unless registration.built_in_save?
        next unless registration.matches_recording?(recording)

        Fanout.publish(event_name: registration.name, recording_id: recording.id)
      end
    end

    def notify_named(name, recording:)
      registration = RecordingStudioMcp.configuration.event_catalog.fetch(name)
      raise ArgumentError, "unregistered event: #{name}" if registration.nil?
      raise ArgumentError, "recording is required" if recording.nil?
      return unless registration.matches_recording?(recording)

      Fanout.publish(event_name: registration.name, recording_id: recording.id)
    end

    def deliver_local(event_name:, recording_id:, recording: nil)
      return unless RecordingStudioMcp.event_registered?(event_name)

      loaded = recording || find_recording(recording_id)
      return if loaded.nil?

      registration = RecordingStudioMcp.configuration.event_catalog.fetch(event_name)
      return if registration.nil? || !registration.matches_recording?(loaded)

      uri = Resources.uri_for(loaded)
      Connections.each do |connection|
        next unless connection.subscribed?(uri)
        next unless still_accessible?(connection, uri, loaded)

        connection.enqueue_updated(uri)
      end
    end

    def recording_from(event)
      return event.recording if event.respond_to?(:recording) && event.recording
      return unless event.respond_to?(:recording_id) && event.recording_id

      find_recording(event.recording_id)
    end
    private_class_method :recording_from

    def find_recording(recording_id)
      return unless defined?(RecordingStudio::Recording)

      RecordingStudio::Recording.find_by(id: recording_id)
    end
    private_class_method :find_recording

    def still_accessible?(connection, uri, recording)
      return Resources.accessible?(connection.access_grant, uri) if recording.nil?

      scope = Resources.accessible_scope(connection.access_grant)
      return false if scope.nil?

      scope.exists?(id: recording.id)
    end
    private_class_method :still_accessible?
  end
end
