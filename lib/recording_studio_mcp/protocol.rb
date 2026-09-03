# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    JSONRPC_VERSION = "2.0"
    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602
    INTERNAL_ERROR = -32_603

    Result = Struct.new(:status, :body, :notification, keyword_init: true)

    def self.handle(payload, access_grant:, idempotency_key: nil)
      new(access_grant: access_grant, idempotency_key: idempotency_key).handle(payload)
    end

    def initialize(access_grant:, idempotency_key: nil)
      @access_grant = access_grant
      @idempotency_key = idempotency_key
    end

    def handle(payload)
      message = parse(payload)
      return rpc_error(nil, PARSE_ERROR, "Parse error") if message == :parse_error
      return rpc_error(nil, INVALID_REQUEST, "Invalid Request") unless valid_request?(message)

      dispatch(message)
    rescue StandardError => e
      rpc_error(message.is_a?(Hash) ? message["id"] : nil, INTERNAL_ERROR, e.message)
    end

    private

    attr_reader :access_grant, :idempotency_key

    def parse(payload)
      return payload if payload.is_a?(Hash)

      JSON.parse(payload)
    rescue JSON::ParserError, TypeError
      :parse_error
    end

    def valid_request?(message)
      return false unless message.is_a?(Hash)

      message["jsonrpc"] == JSONRPC_VERSION && message["method"].present?
    end

    def dispatch(message)
      method_name = message["method"].to_s
      params = message["params"] || {}
      id = message["id"]
      notification = !message.key?("id")

      result =
        case method_name
        when "initialize"
          initialize_result(params)
        when "notifications/initialized", "notifications/cancelled"
          :ok
        when "ping"
          {}
        when "tools/list"
          { tools: Tools.definitions(access_grant: access_grant) }
        when "tools/call"
          call_tool(params)
        else
          return rpc_error(id, METHOD_NOT_FOUND, "Method not found")
        end

      return Result.new(status: :accepted, body: nil, notification: true) if notification

      Result.new(status: :ok, body: { jsonrpc: JSONRPC_VERSION, id: id, result: result }, notification: false)
    end

    def initialize_result(params)
      requested = params["protocolVersion"].to_s
      version =
        if Configuration::SUPPORTED_PROTOCOL_VERSIONS.include?(requested)
          requested
        else
          RecordingStudioMcp.configuration.protocol_version
        end

      {
        protocolVersion: version,
        capabilities: { tools: { listChanged: true } },
        serverInfo: {
          name: "recording-studio",
          version: RecordingStudioMcp::VERSION
        }
      }
    end

    def call_tool(params)
      name = params["name"].to_s
      arguments = params["arguments"] || {}
      return rpc_invalid_params("name is required") if name.blank?

      Dispatcher.call(
        tool_name: name,
        arguments: arguments,
        access_grant: access_grant,
        idempotency_key: idempotency_key
      )
    end

    def rpc_invalid_params(message)
      raise ArgumentError, message
    end

    def rpc_error(id, code, message)
      Result.new(
        status: :ok,
        notification: false,
        body: {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          error: { code: code, message: message }
        }
      )
    end
  end
end
