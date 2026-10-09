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
      :status,
      :body,
      :notification,
      :session_id,
      :listen,
      :listen_connection,
      keyword_init: true
    )

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
          initialize_result(params, id)
        when "server/discover"
          discover_result
        when "notifications/initialized", "notifications/cancelled"
          :ok
        when "ping"
          ResultShape.complete({}, protocol_version: request_protocol_version, cacheable: false)
        when "tools/list"
          ResultShape.complete(
            { tools: Tools.definitions(access_grant: access_grant) },
            protocol_version: request_protocol_version
          )
        when "tools/call"
          call_tool(params, id)
        when "skills/list", "skills/get"
          skill_result(method_name, params, id)
        when "resources/list"
          resources_list(params, id)
        when "resources/templates/list"
          resources_templates(params, id)
        when "resources/read"
          resources_read(params, id)
        when "resources/subscribe"
          subscribe_resource(params, id)
        when "resources/unsubscribe"
          unsubscribe_resource(params, id)
        when "subscriptions/listen"
          listen_subscriptions(params, id)
        when "events/list", "events/subscribe", "events/unsubscribe"
          events_result(method_name, params, id)
        else
          return rpc_error(id, METHOD_NOT_FOUND, "Method not found")
        end

      return result if result.is_a?(Result)
      return Result.new(status: :accepted, body: nil, notification: true) if notification

      Result.new(status: :ok, body: { jsonrpc: JSONRPC_VERSION, id: id, result: result }, notification: false)
    end

    def initialize_result(params, id)
      requested = params["protocolVersion"].to_s
      version =
        if Configuration::SUPPORTED_PROTOCOL_VERSIONS.include?(requested)
          requested
        else
          RecordingStudioMcp.configuration.protocol_version
        end

      session_id = open_legacy_session(version)
      Result.new(
        status: :ok,
        notification: false,
        session_id: session_id,
        body: {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: {
            protocolVersion: version,
            capabilities: server_capabilities,
            serverInfo: self.class.server_info,
            instructions: Instructions.text(access_grant: access_grant)
          }
        }
      )
    end

    def discover_result
      # server/discover is a 2026-07-28 method. The result is always DiscoverResult,
      # including when a client omitted MCP-Protocol-Version.
      ResultShape.complete(
        {
          supportedVersions: Configuration::SUPPORTED_PROTOCOL_VERSIONS,
          capabilities: server_capabilities,
          instructions: Instructions.text(access_grant: access_grant)
        },
        protocol_version: Configuration::MODERN_PROTOCOL_VERSION
      )
    end

    def server_capabilities
      capabilities = {
        tools: { listChanged: false },
        resources: resources_capability,
        extensions: { "io.modelcontextprotocol/skills" => {} }
      }
      capabilities[:events] = {} if RecordingStudioMcp.configuration.events_enabled
      capabilities
    end

    def resources_capability
      return {} unless RecordingStudioMcp.events_registered?

      { subscribe: true }
    end

    def open_legacy_session(version)
      return unless Configuration.legacy_protocol?(version)
      return unless request_context

      connection = Connections.open(protocol_version: version, access_grant: access_grant)
      request_context.attach_connection(connection)
      connection.id
    end

    def resources_list(params, id)
      answer = Resources.list(
        access_grant: access_grant,
        cursor: params["cursor"],
        protocol_version: request_protocol_version
      )
      case answer
      when Resources::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Resources::List
        answer.payload
      else
        raise TypeError, "unexpected resources list answer"
      end
    end

    def resources_templates(params, id)
      answer = Resources.templates(cursor: params["cursor"], protocol_version: request_protocol_version)
      case answer
      when Resources::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Resources::Templates
        answer.payload
      else
        raise TypeError, "unexpected resources templates answer"
      end
    end

    def resources_read(params, id)
      uri = params["uri"]
      return skill_result("resources/read", params, id) if Skills::SkillName.from_uri(uri)

      answer = Resources.read(
        access_grant: access_grant,
        uri: uri,
        protocol_version: request_protocol_version
      )
      case answer
      when Resources::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Resources::NotFound
        # 2026-07-28 resources page: not found MUST be -32602. 2025 pages use -32002.
        rpc_error(id, resource_not_found_code, "Resource not found", data: { uri: answer.uri })
      when Resources::Read
        answer.payload
      else
        raise TypeError, "unexpected resources read answer"
      end
    end

    def subscribe_resource(params, id)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless subscribe_enabled?
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") if modern_request?

      uri = params["uri"].to_s
      # 2025-06-18 resources page: unknown URI SHOULD be -32002 Resource not found.
      unless Resources.accessible?(access_grant, uri)
        return rpc_error(id, RESOURCE_NOT_FOUND, "Resource not found", data: { uri: uri })
      end

      connection = legacy_connection
      return rpc_error(id, INVALID_PARAMS, "No listening session") if connection.nil?

      connection.subscribe(uri)
      {}
    end

    def unsubscribe_resource(params, id)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless subscribe_enabled?
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") if modern_request?

      connection = legacy_connection
      return rpc_error(id, INVALID_PARAMS, "No listening session") if connection.nil?

      connection.unsubscribe(params["uri"].to_s)
      {}
    end

    def listen_subscriptions(params, id)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless subscribe_enabled?
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless modern_request?

      uris = Array((params["notifications"] || {})["resourceSubscriptions"]).map(&:to_s)
      allowed = uris.select { |uri| Resources.accessible?(access_grant, uri) }
      connection = Connections.open(
        protocol_version: request_protocol_version,
        access_grant: access_grant,
        subscription_id: id
      )
      allowed.each { |uri| connection.subscribe(uri) }
      request_context&.attach_connection(connection)

      Result.new(
        status: :ok,
        body: nil,
        notification: false,
        listen: true,
        listen_connection: connection
      )
    end

    def events_result(method_name, params, id)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless RecordingStudioMcp.configuration.events_enabled

      answer =
        case method_name
        when "events/list"
          EventRpc.list(params: params, protocol_version: request_protocol_version)
        when "events/subscribe"
          EventRpc.subscribe(params: params, access_grant: access_grant, protocol_version: request_protocol_version)
        else
          EventRpc.unsubscribe(params: params, access_grant: access_grant)
        end

      case answer
      when EventRpc::Error
        rpc_error(id, answer.code, answer.message, data: answer.data)
      when EventRpc::Answer
        answer.payload
      else
        raise TypeError, "unexpected events answer"
      end
    end

    def subscribe_enabled?
      RecordingStudioMcp.events_registered?
    end

    def modern_request?
      Configuration.modern_protocol?(request_protocol_version)
    end

    def request_protocol_version
      request_context&.protocol_version.presence || RecordingStudioMcp.configuration.protocol_version
    end

    def legacy_connection
      request_context&.connection
    end

    def resource_not_found_code
      modern_request? ? INVALID_PARAMS : RESOURCE_NOT_FOUND
    end

    def skill_result(method_name, params, id)
      answer = Skills.answer(
        method_name,
        params,
        access_grant: access_grant,
        protocol_version: request_protocol_version
      )
      case answer
      when Skills::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Skills::Unavailable
        rpc_error(id, INTERNAL_ERROR, "Skill content is unavailable")
      when Skills::Result
        answer.payload
      else
        raise TypeError, "unexpected skill answer"
      end
    end

    def call_tool(params, id)
      name = params["name"].to_s
      arguments = params["arguments"] || {}
      return rpc_error(id, INVALID_PARAMS, "name is required") if name.blank?

      ResultShape.complete(
        Dispatcher.call(
          tool_name: name,
          arguments: arguments,
          access_grant: access_grant,
          idempotency_key: idempotency_key,
          request_context: request_context,
          meta: params["_meta"] || params[:_meta]
        ),
        protocol_version: request_protocol_version,
        cacheable: false
      )
    end

    def rpc_error(id, code, message, data: nil)
      error = { code: code, message: message }
      error[:data] = data if data
      Result.new(
        status: :ok,
        notification: false,
        body: {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          error: error
        }
      )
    end
  end
end
