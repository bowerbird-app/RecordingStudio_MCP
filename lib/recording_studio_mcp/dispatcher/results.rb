# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def render_handler_result(result)
      json = result.fetch(:json)
      status = result.fetch(:status, :ok)
      return success_result(json) if SUCCESS_STATUS_RANGE.cover?(Rack::Utils.status_code(status))

      error_result(handler_error_message(json))
    end

    def handler_error_message(json)
      payload = stringify_payload(json)
      hash_error_message(payload) || (payload.is_a?(Hash) ? JSON.generate(payload) : payload.to_s)
    end

    def hash_error_message(payload)
      return unless payload.is_a?(Hash)

      message = payload.dig("error", "message") || payload["message"]
      return message if message.present?
      return payload["error"] if payload["error"].is_a?(String)

      nil
    end

    def progress_reporter
      request_context&.progress_reporter
    end

    def api_key
      catalog.api
    end

    def api_version
      RecordingStudioApi.default_api_version(api: api_key)
    end

    def argument_object?(value)
      value.nil? || value.is_a?(Hash) || parameter_object?(value)
    end

    def parameter_object?(value)
      value.respond_to?(:to_unsafe_h) && !value.is_a?(String)
    end

    def validate_index_arguments!(args)
      reject_filter!(args["filter"])
      reject_limit!(args["limit"])
    end

    def reject_filter!(filter)
      return if filter.blank?
      raise RecordingStudioApi::InvalidActionInputError, "filter must be an object" unless argument_object?(filter)

      filter_pairs(filter).each do |key, value|
        next if filter_value?(value)

        raise RecordingStudioApi::InvalidActionInputError, "Invalid filter #{key}"
      end
    end

    def reject_limit!(limit)
      return if limit.blank? || numeric_limit?(limit)

      raise RecordingStudioApi::InvalidActionInputError, "limit must be a number"
    end

    def filter_pairs(filter)
      source = parameter_object?(filter) ? filter.to_unsafe_h : filter
      source.to_h
    end

    def filter_value?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end

    def numeric_limit?(limit)
      return true if limit.is_a?(Numeric)
      return false unless limit.is_a?(String)

      limit.match?(/\A-?\d+\z/)
    end

    def stringify_keys(value)
      return {} if value.blank?
      return value.to_unsafe_h.stringify_keys if value.respond_to?(:to_unsafe_h)
      return value.to_h.stringify_keys if value.respond_to?(:to_h)

      {}
    end

    def unknown_tool_message(name)
      allowed = surface.tool_names
      suffix = allowed.any? ? allowed.join(", ") : "(none)"
      "Unknown tool #{name}. Allowed tools: #{suffix}"
    end

    def success_result(payload)
      json = stringify_payload(payload)
      {
        content: [{ type: "text", text: JSON.generate(json) }],
        structuredContent: json,
        isError: false
      }
    end

    def stringify_payload(payload)
      JSON.parse(JSON.generate(payload))
    rescue JSON::GeneratorError, TypeError
      payload
    end

    def error_result(message)
      {
        content: [{ type: "text", text: message.to_s }],
        isError: true
      }
    end
  end
end
