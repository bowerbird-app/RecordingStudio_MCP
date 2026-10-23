# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    JSONRPC_VERSION = "2.0"
    SERVER_NAME = "recording-studio"
    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602
    INTERNAL_ERROR = -32_603
    RESOURCE_NOT_FOUND = Resources::RESOURCE_NOT_FOUND
    HEADER_MISMATCH = -32_020
    UNSUPPORTED_PROTOCOL_VERSION = -32_022

    Result = Struct.new(
      :status, :body, :notification, :session_id, :listen, :listen_connection,
      keyword_init: true
    )

    HANDLERS = {
      "initialize" => :initialize_result,
      "server/discover" => :discover_result,
      "notifications/initialized" => :ok_notification,
      "notifications/cancelled" => :ok_notification,
      "ping" => :ping_result,
      "tools/list" => :tools_list_result,
      "tools/call" => :call_tool,
      "skills/list" => :skill_result,
      "skills/get" => :skill_result,
      "resources/list" => :resources_list,
      "resources/templates/list" => :resources_templates,
      "resources/read" => :resources_read,
      "resources/subscribe" => :subscribe_resource,
      "resources/unsubscribe" => :unsubscribe_resource,
      "subscriptions/listen" => :listen_subscriptions,
      "events/list" => :events_result,
      "events/subscribe" => :events_result,
      "events/unsubscribe" => :events_result
    }.freeze

    def self.handle(payload, access_grant:, idempotency_key: nil, request_context: nil)
      new(
        access_grant: access_grant,
        idempotency_key: idempotency_key,
        request_context: request_context
      ).handle(payload)
    end

    def self.server_info
      { name: SERVER_NAME, version: RecordingStudioMcp::VERSION }
    end

    def initialize(access_grant:, idempotency_key: nil, request_context: nil)
      @access_grant = access_grant
      @idempotency_key = idempotency_key
      @request_context = request_context
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

    attr_reader :access_grant, :idempotency_key, :request_context
  end
end

require "recording_studio_mcp/protocol/rpc"
require "recording_studio_mcp/protocol/lifecycle"
require "recording_studio_mcp/protocol/tools_rpc"
require "recording_studio_mcp/protocol/resources_rpc"
require "recording_studio_mcp/protocol/subscriptions_rpc"
require "recording_studio_mcp/protocol/events_rpc"
