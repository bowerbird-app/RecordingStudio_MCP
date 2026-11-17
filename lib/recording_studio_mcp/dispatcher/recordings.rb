# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def load_recording(recordable_type, id, include_trashed: false)
      raise RecordingStudioApi::InvalidActionInputError, "id is required" if id.blank?

      recording = scoped_recordings(include_trashed).find_by(id: id)
      raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?

      unless recording.recordable_type == recordable_type
        shown = catalog.displayed_type_name(recordable_type)
        raise RecordingStudioApi::NotFoundError, "Resource type does not match #{shown}"
      end

      recording
    end

    def scoped_recordings(include_trashed)
      return access_grant.accessible_recordings(include_trashed: true) if include_trashed

      access_grant.accessible_recordings
    end

    def serialize_capability_result(action, result, args = {})
      return result.fetch(:json) if result.is_a?(Hash) && result.key?(:json)

      serializer = action.serializer || RecordingStudioApi::Serializers::ResourceRecordingSerializer
      return recording_serializer_call(serializer, result, args) if default_recording_serializer?(serializer)

      serializer.call(result)
    end

    def recording_serializer_call(serializer, result, args)
      serializer.call(
        result,
        version: api_version,
        api: api_key,
        context: recording_context_for(result, args)
      )
    end

    def recording_context_for(result, args)
      RecordingStudioApi::RelationshipContext.for(
        recordings: recording_result?(result) ? [result] : [],
        include_values: args["include"],
        scoped_recordings: access_grant.accessible_recordings,
        api_key: api_key,
        api_version: api_version,
        access_grant: access_grant,
        params: args
      )
    end

    def recording_result?(result)
      result.respond_to?(:recordable_type) && result.respond_to?(:recordable)
    end

    def default_recording_serializer?(serializer)
      serializer == RecordingStudioApi::Serializers::ResourceRecordingSerializer
    end
  end
end
