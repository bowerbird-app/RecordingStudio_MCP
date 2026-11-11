# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    API_TOOL_ERRORS = [
      RecordingStudioApi::AuthorizationError,
      RecordingStudioApi::NotFoundError,
      RecordingStudioApi::UnsupportedActionError,
      RecordingStudioApi::InvalidActionInputError,
      RecordingStudioApi::InvalidPaginationTokenError
    ].freeze
    DOMAIN_TOOL_ERRORS = [
      ActiveRecord::RecordInvalid,
      RecordingStudio::AuthorizationError,
      RecordingStudio::ActorRequired,
      RecordingStudio::InvalidParent
    ].freeze
    TOOL_ERROR_CLASSES = (API_TOOL_ERRORS + DOMAIN_TOOL_ERRORS).freeze

    private

    def tool_error_for(error)
      if API_TOOL_ERRORS.any? { |klass| error.is_a?(klass) }
        return error_result(error.message, details: copied_details(error))
      end
      return error_result(record_invalid_tool_message(error)) if error.is_a?(ActiveRecord::RecordInvalid)
      return error_result(error.message) if error.is_a?(RecordingStudio::ActorRequired)
      return error_result(error.message) if error.is_a?(RecordingStudio::InvalidParent)

      error_result("Not authorized")
    end

    def record_invalid_tool_message(error)
      messages = error.record&.errors&.full_messages
      messages.present? ? messages.to_sentence : error.message.to_s
    end

    def copied_details(error)
      error.details if error.respond_to?(:details)
    end
  end
end
