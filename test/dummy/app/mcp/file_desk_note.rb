# frozen_string_literal: true

module Dummy
  class FileDeskNote
    def self.call(context)
      params = context.params || {}
      if params.key?(:parent_id) || params.key?("parent_id")
        raise RecordingStudioApi::InvalidActionInputError, "parent_id is not accepted"
      end

      note = params[:note] || params["note"]
      parent = context.recording
      recording = RecordingStudio.record!(
        action: "created",
        recordable: Page.create!(title: note),
        root_recording: parent.root_recording || parent,
        parent_recording: parent,
        actor: actor_for(context)
      ).recording
      {
        json: {
          "id" => recording.id.to_s,
          "parent_id" => recording.parent_recording_id.to_s,
          "title" => note
        }
      }
    end

    def self.actor_for(context)
      grant = context.access_grant
      actor = grant.actor if grant.respond_to?(:actor)
      return actor if actor.present?

      grant.api_client
    end
  end
end
