# frozen_string_literal: true

module RecordingStudioMcp
  module Api
    module Access
      module_function

      def can_view?(context)
        actor = context.access_grant.actor
        recording = admin_root_recording
        return false if actor.blank? || recording.blank?

        RecordingStudioAccessible.authorized?(
          actor: actor,
          recording: recording,
          role: :view
        )
      end

      def admin_root_recording
        RecordingStudioAdmin.configuration.access_recording_resolver.call(nil)
      end
    end
  end
end
