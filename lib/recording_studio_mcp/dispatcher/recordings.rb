# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def load_recording(recordable_type, id, include_trashed: false)
      raise RecordingStudioApi::InvalidActionInputError, "id is required" if id.blank?

      recording = scoped_recordings(include_trashed).find_by(id: id)
      raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
      unless recording.recordable_type == recordable_type
        raise RecordingStudioApi::NotFoundError, "Resource type does not match #{recordable_type}"
      end

      recording
    end

    def scoped_recordings(include_trashed)
      return access_grant.accessible_recordings(include_trashed: true) if include_trashed

      access_grant.accessible_recordings
    end

    def serialize_capability_result(action, result)
      return result.fetch(:json) if result.is_a?(Hash) && result.key?(:json)

      serializer = action.serializer || RecordingStudioApi::Serializers::ResourceRecordingSerializer
      return serializer.call(result, version: api_version, api: api_key) if default_recording_serializer?(serializer)

      serializer.call(result)
    end

    def default_recording_serializer?(serializer)
      serializer == RecordingStudioApi::Serializers::ResourceRecordingSerializer
    end
  end
end
