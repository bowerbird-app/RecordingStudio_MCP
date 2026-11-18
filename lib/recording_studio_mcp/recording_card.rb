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
      title.presence || "#{shown_type} #{@recording.id}"
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

      label = studio_name(recordable)
      label = nil if generated_fallback?(recordable, label)
      label.presence || field(recordable, :name).presence || field(recordable, :title)
    end

    private

    def shown_type
      @catalog.displayed_type_name(@recording.recordable_type)
    end

    def generated_fallback?(recordable, label)
      return false if label.blank?

      class_name = fallback_class_name(recordable)
      return true if label == class_name

      identifier = recordable.id if recordable.respond_to?(:id)
      identifier.present? && label == "#{class_name} ##{identifier}"
    end

    def fallback_class_name(recordable)
      recordable.class.name.to_s.squish.presence || recordable.class.to_s
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
