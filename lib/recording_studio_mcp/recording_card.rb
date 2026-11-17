# frozen_string_literal: true

module RecordingStudioMcp
  class RecordingCard
    def initialize(recording, catalog:)
      @recording = recording
      @catalog = catalog
    end

    def list_entry
      { uri: uri, name: name, mimeType: Resources::MIME_TYPE }
    end

    def content
      { uri: uri, mimeType: Resources::MIME_TYPE, text: JSON.generate(payload) }
    end

    def uri
      Resources.uri_for(@recording)
    end

    def name
      title.presence || shown_type
    end

    def payload
      {
        id: @recording.id,
        type: shown_type,
        name: name,
        parent_id: @recording.parent_recording_id,
        root_id: @recording.root_recording_id,
        title: title
      }.compact
    end

    def title
      recordable = @recording.recordable
      return if recordable.nil?

      studio_name(recordable).presence || field(recordable, :name).presence || field(recordable, :title)
    end

    private

    def shown_type
      @catalog.displayed_type_name(@recording.recordable_type)
    end

    def studio_name(recordable)
      return unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:recordable_name)

      RecordingStudio.recordable_name(recordable)
    rescue StandardError
      nil
    end

    def field(recordable, attribute)
      return unless recordable.respond_to?(attribute)

      recordable.public_send(attribute)
    end
  end
end
