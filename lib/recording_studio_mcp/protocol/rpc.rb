# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    private

    def parse(payload)
      return payload if payload.is_a?(Hash)

      JSON.parse(payload)
    rescue JSON::ParserError, TypeError
      :parse_error
    end

    def valid_request?(message)
      message.is_a?(Hash) && message["jsonrpc"] == JSONRPC_VERSION && message["method"].present?
    end

    def dispatch(message)
      method_name = message["method"].to_s
      handler = HANDLERS[method_name]
      return rpc_error(message["id"], METHOD_NOT_FOUND, "Method not found") if handler.nil?

      finish_rpc(message, send(handler, message["params"] || {}, message["id"], method_name))
    end

    def finish_rpc(message, result)
      return result if result.is_a?(Result)
      return Result.new(status: :accepted, body: nil, notification: true) unless message.key?("id")

      body = { jsonrpc: JSONRPC_VERSION, id: message["id"], result: result }
      Result.new(status: :ok, body: body, notification: false)
    end

    def rpc_error(id, code, message, data: nil)
      error = { code: code, message: message }
      error[:data] = data if data
      Result.new(status: :ok, notification: false, body: { jsonrpc: JSONRPC_VERSION, id: id, error: error })
    end

    def request_protocol_version
      request_context&.protocol_version.presence || RecordingStudioMcp.configuration.protocol_version
    end

    def modern_request?
      Configuration.modern_protocol?(request_protocol_version)
    end
  end
end
