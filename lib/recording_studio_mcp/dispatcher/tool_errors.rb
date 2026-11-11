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
      error_result(tool_error_message(error), details: tool_error_details(error))
    end

    def tool_error_message(error)
      return record_invalid_tool_message(error) if error.is_a?(ActiveRecord::RecordInvalid)
      return "Not authorized" if error.is_a?(RecordingStudio::AuthorizationError)
      return actor_required_tool_message(error) if error.is_a?(RecordingStudio::ActorRequired)
      return invalid_parent_tool_message(error) if error.is_a?(RecordingStudio::InvalidParent)

      error.message
    end

    def record_invalid_tool_message(error)
      messages = error.record&.errors&.full_messages
      messages.present? ? messages.to_sentence : error.message.to_s
    end

    def actor_required_tool_message(error)
      message = error.message.to_s
      return message if message.present? && message != error.class.name

      "actor is required"
    end

    def invalid_parent_tool_message(error)
      message = error.message.to_s
      return "parent_id is not allowed" if message.blank? || message == error.class.name
      return message if message.include?("parent_id")

      "parent_id is not allowed: #{message}"
    end

    def tool_error_details(error)
      if error.respond_to?(:details)
        details = error.details
        return details if details.present?
      end
      return { "parent_id" => invalid_parent_tool_message(error) } if error.is_a?(RecordingStudio::InvalidParent)

      nil
    end

    def error_result(message, details: nil)
      result = {
        content: [{ type: "text", text: message.to_s }],
        isError: true
      }
      return result if details.blank?

      result[:structuredContent] = { "details" => stringify_payload(details) }
      result
    end
  end
end
