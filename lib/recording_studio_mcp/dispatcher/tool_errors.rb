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
      RecordingStudio::InvalidParent,
      RecordingStudio::AuthorizationError
    ].freeze
    TOOL_ERROR_CLASSES = (API_TOOL_ERRORS + DOMAIN_TOOL_ERRORS).freeze

    private

    def tool_error_for(error)
      return error_result(error.message) if API_TOOL_ERRORS.any? { |klass| error.is_a?(klass) }
      return error_result(record_invalid_tool_message(error)) if error.is_a?(ActiveRecord::RecordInvalid)
      return error_result(invalid_parent_tool_message(error)) if error.is_a?(RecordingStudio::InvalidParent)
      return error_result("Not authorized") if error.is_a?(RecordingStudio::AuthorizationError)

      nil
    end

    def record_invalid_tool_message(error)
      messages = error.record&.errors&.full_messages
      messages.present? ? messages.to_sentence : error.message.to_s
    end

    def invalid_parent_tool_message(error)
      [error.message.presence, "parent_id"].compact.join(" ")
    end
  end
end
