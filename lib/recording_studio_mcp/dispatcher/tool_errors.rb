# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    API_TOOL_ERRORS = [
      RecordingStudioApi::AuthorizationError,
      RecordingStudioApi::NotFoundError,
      RecordingStudioApi::UnsupportedActionError,
      RecordingStudioApi::InvalidActionInputError,
      RecordingStudioApi::InvalidPaginationTokenError,
      RecordingStudioApi::IdempotencyKeyMismatchError
    ].freeze
    DOMAIN_TOOL_ERRORS = [
      ActiveRecord::RecordInvalid,
      RecordingStudio::AuthorizationError,
      RecordingStudio::ActorRequired,
      RecordingStudio::InvalidParent,
      RecordingStudio::Denial
    ].freeze
    TOOL_ERROR_CLASSES = (API_TOOL_ERRORS + DOMAIN_TOOL_ERRORS).freeze
    PARENT_NOT_FOUND = "Parent resource was not found in this API scope"
    BUSY_CHANGE = "Another change to this item is in progress. Try again."

    private

    def tool_error_for(error)
      return api_error_result(error) if API_TOOL_ERRORS.any? { |klass| error.is_a?(klass) }
      return error_result(record_invalid_tool_message(error)) if error.is_a?(ActiveRecord::RecordInvalid)
      return error_result(error.message) if error.is_a?(RecordingStudio::ActorRequired)
      return error_result(error.message) if error.is_a?(RecordingStudio::InvalidParent)
      return denial_tool_error(error) if error.is_a?(RecordingStudio::Denial)

      error_result("Not authorized")
    end

    def denial_tool_error(error)
      interpreted = RecordingStudioApi::BillingDenial.interpret(error)
      if interpreted
        return error_result(
          interpreted.fetch(:message),
          details: interpreted[:details],
          code: interpreted[:code]
        )
      end

      error_result(unrecognized_denial_message)
    end

    def unrecognized_denial_message
      if defined?(RecordingStudioApi::Concerns::BillingDenials::UNRECOGNIZED_DENIAL_MESSAGE)
        RecordingStudioApi::Concerns::BillingDenials::UNRECOGNIZED_DENIAL_MESSAGE
      else
        "This action is not allowed"
      end
    end

    def api_error_result(error)
      if error.is_a?(RecordingStudioApi::IdempotencyKeyMismatchError)
        return error_result(error.message, code: error.code)
      end

      error_result(tool_error_message(error), details: copied_details(error))
    end

    def tool_error_message(error)
      message = error.message.to_s
      return message unless message == PARENT_NOT_FOUND && @parent_hint_type
      return message unless catalog.respond_to?(:parent_rules_for)

      parent_not_found_message(@parent_hint_type)
    end

    def parent_not_found_message(recordable_type)
      types = Array(catalog.parent_rules_for(recordable_type)["allowed_parent_types"])
      listed = types.any? ? types.join(", ") : "(none)"
      message = "#{PARENT_NOT_FOUND} Allowed parent types: #{listed}."
      workspace_id = catalog.workspace_parent_id(recordable_type)
      return message if workspace_id.blank?

      "#{message} Workspace id: #{workspace_id}."
    end

    def unexpected_tool_error(error)
      log_tool_error(error)
      error_result("Internal error")
    end

    def retryable_busy_error(error)
      log_tool_error(error)
      error_result(BUSY_CHANGE)
    end

    def busy_database_error?(error)
      return true if error.is_a?(ActiveRecord::Deadlocked)
      return true if defined?(ActiveRecord::LockWaitTimeout) && error.is_a?(ActiveRecord::LockWaitTimeout)

      lock_timeout_cancel?(error)
    end

    def lock_timeout_cancel?(error)
      return false unless defined?(ActiveRecord::QueryCanceled) && error.is_a?(ActiveRecord::QueryCanceled)

      error.message.to_s.match?(/lock timeout/i)
    end

    def log_tool_error(error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.error("[RecordingStudioMcp::Dispatcher] #{error.class}")
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
