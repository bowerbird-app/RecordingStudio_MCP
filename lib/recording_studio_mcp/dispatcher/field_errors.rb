# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    module FieldErrors
      private

      def reject_immutable_update_fields!(recordable_type, payload, allowed)
        frozen = payload.keys & (catalog.writable_fields(recordable_type) - allowed)
        return if frozen.empty?

        raise RecordingStudioApi::InvalidActionInputError,
              "#{frozen.sort.join(', ')} cannot be changed on update. " \
              "#{writable_fields_sentence(recordable_type, allowed)}"
      end

      def reject_unknown_keys!(recordable_type, payload, allowed)
        unknown = payload.keys - allowed
        return if unknown.empty?

        raise RecordingStudioApi::InvalidActionInputError, unknown_fields_message(recordable_type, unknown, allowed)
      end

      def unknown_fields_message(recordable_type, unknown, allowed)
        "Unknown fields #{unknown.sort.join(', ')}. #{writable_fields_sentence(recordable_type, allowed)}"
      end

      def writable_fields_sentence(recordable_type, allowed)
        listed = allowed.any? ? allowed.join(", ") : "(none)"
        "Writable fields for #{catalog.displayed_type_name(recordable_type)}: #{listed}"
      end
    end
  end
end
