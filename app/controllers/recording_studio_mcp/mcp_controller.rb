# frozen_string_literal: true

module RecordingStudioMcp
  class McpController < ActionController::API
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging

    prepend_before_action :authenticate_mcp!
    include RecordingStudioMcp::TransportSecurity
    include RecordingStudioApi::Concerns::ApiAccessControl
    include RecordingStudioMcp::UsageLogging

    def handle
      return listen_get if request.get?
      return head :method_not_allowed unless request.post?

      request_context = build_request_context
      return stream_mcp(request_context) if stream_tool_call?(request_context)
      return stream_listen(request_context) if jsonrpc_method == "subscriptions/listen"

      result = dispatch_protocol(request_context)
      assign_session_header(result.session_id)
      return head :accepted if result.notification && result.body.nil?

      render json: result.body, status: result.status
    end

    private

    def stream_tool_call?(request_context)
      StreamDecision.stream?(
        method_name: jsonrpc_method,
        params: jsonrpc_params,
        accept_header: request.headers["Accept"]
      ) && request_context.progress_token
    end

    def stream_listen?(request_context)
      StreamDecision.listen?(
        method_name: jsonrpc_method,
        protocol_version: request_context.protocol_version,
        accept_header: request.headers["Accept"]
      )
    end

    def listen_get
      request_context = build_request_context
      return head :method_not_allowed unless legacy_get_listen?(request_context)

      connection = existing_or_open_legacy_connection(request_context)
      return head :bad_request if connection.nil?

      assign_session_header(connection.id)
      stream_listen_connection(request_context, connection, write_ack: false)
    end

    def legacy_get_listen?(request_context)
      RecordingStudioMcp.events_registered? &&
        StreamDecision.legacy_get_listen?(
          protocol_version: request_context.protocol_version,
          accept_header: request.headers["Accept"]
        )
    end

    def stream_listen(request_context)
      result = dispatch_protocol(request_context)
      return render json: result.body, status: result.status unless result.listen

      stream_listen_connection(request_context, result.listen_connection, write_ack: true)
    end

    def stream_mcp(request_context)
      @mcp_stream = true
      assign_sse_headers
      self.response_body = stream_body_for(request_context)
    end

    def stream_listen_connection(request_context, connection, write_ack:)
      @mcp_stream = true
      assign_sse_headers
      self.response_body = listen_stream_body(request_context, connection, write_ack)
    end

    def listen_stream_body(request_context, connection, write_ack)
      payload = request.get? ? { "method" => "listen" } : jsonrpc_payload
      call = ListenStream.new(
        connection: connection,
        request_context: request_context,
        write_ack: write_ack
      )
      stream_body(request_context, call, payload, current_api_client&.id, connection)
    end

    def stream_body(request_context, call, payload, api_client_id, connection = nil)
      SseStreamBody.new(
        on_disconnect: lambda {
          request_context.disconnect!
          connection&.finish!
        },
        on_abort: -> { record_stream_usage(payload, api_client_id, nil, disconnected: true) },
        on_run: ->(writer) { finish_stream(call, writer, payload, api_client_id) }
      )
    end

    def stream_body_for(request_context)
      stream_body(request_context, streamed_call_for(request_context), jsonrpc_payload, current_api_client&.id)
    end

    def existing_or_open_legacy_connection(request_context)
      connection = request_context.connection
      return connection if connection

      opened = Connections.open(
        protocol_version: request_context.protocol_version,
        access_grant: @access_grant
      )
      request_context.attach_connection(opened)
      opened
    end

    def assign_session_header(session_id)
      return if session_id.blank?

      response.headers["Mcp-Session-Id"] = session_id
    end

    def streamed_call_for(request_context)
      StreamedCall.new(
        request_context: request_context,
        access_grant: @access_grant,
        raw_payload: request_payload,
        idempotency_key: request.headers["Idempotency-Key"].presence
      )
    end

    def finish_stream(call, writer, payload, api_client_id)
      release_idle_database_connections
      result = nil
      result = call.perform(writer)
    ensure
      record_stream_usage(
        payload,
        api_client_id,
        result,
        disconnected: call.disconnected?(writer)
      )
    end

    def dispatch_protocol(request_context)
      Protocol.handle(
        request_payload,
        access_grant: @access_grant,
        idempotency_key: request.headers["Idempotency-Key"].presence,
        request_context: request_context
      )
    end

    def build_request_context
      context = RequestContext.new(
        request_id: jsonrpc_payload["id"],
        protocol_version: effective_protocol_version,
        access_grant: @access_grant,
        progress_token: StreamDecision.progress_token(jsonrpc_params)
      )
      context.attach_connection(Connections.fetch(request.headers["Mcp-Session-Id"]))
      context
    end

    def jsonrpc_params
      params = jsonrpc_payload["params"]
      params.is_a?(Hash) ? params : {}
    end

    def assign_sse_headers
      response.status = 200
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache, no-store"
      response.headers["Connection"] = "keep-alive"
      response.headers["X-Accel-Buffering"] = "no"
      response.headers["Last-Modified"] = Time.now.httpdate
      response.headers.delete("Content-Length")
    end

    def release_idle_database_connections
      return unless defined?(ActiveRecord::Base)

      ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    rescue StandardError
      nil
    end

    def ensure_api_access_enabled!
      return if RecordingStudioApi::ApiSetting.api_access_enabled?(api: current_api_key)

      render_api_disabled
    end

    def authenticate_mcp!
      auth = Authenticator.access_grant(request.headers["Authorization"])
      return render_unauthorized(auth) unless auth.success?

      assign_access_grant(auth.access_grant)
      return if RecordingStudioApi::ApiSetting.api_access_enabled?(api: current_api_key)

      render_api_disabled
    end

    def assign_access_grant(grant)
      @access_grant = grant
      @current_api_key = grant.api_client&.api_key.presence || "public"
      @current_api_client = grant.api_client
      @current_api_credential = grant.credential
      @current_access_recording = grant.access_recording
      @current_root_recording = grant.root_recording
      @current_access_grant = grant
    end

    def render_unauthorized(auth)
      error = auth.error == :missing_token ? nil : "invalid_token"
      response.set_header("WWW-Authenticate", WwwAuthenticate.header_value(request, error: error))
      render json: { error: "unauthorized" }, status: :unauthorized
    end

    def render_api_disabled
      render json: api_error_payload(
        code: "api_access_disabled",
        message: "API access is temporarily disabled"
      ), status: :service_unavailable
    end

    def current_api_key
      @current_api_key.presence || "public"
    end

    def current_runtime_policy
      @current_runtime_policy ||= RecordingStudioApi::ApiRuntimePolicy.for(current_api_key)
    end

    attr_reader :current_api_client,
                :current_api_credential,
                :current_access_recording,
                :current_access_grant,
                :current_root_recording

    def api_error_payload(code:, message:, details: nil)
      error = { code: code.to_s, message: message.to_s }
      error[:details] = details if details.present?
      { error: error }
    end

    def api_rate_limited_path?
      true
    end

    def api_read_request?
      method_name = jsonrpc_method
      return true if %w[
        initialize ping tools/list skills/list skills/get server/discover
        resources/list resources/read resources/subscribe resources/unsubscribe
        subscriptions/listen
      ].include?(method_name)
      return false unless method_name == "tools/call"

      ToolSurface.for(access_grant: @access_grant).read_only_tool?(jsonrpc_tool_name)
    end

    def jsonrpc_method
      jsonrpc_payload["method"].to_s
    end

    def jsonrpc_tool_name
      jsonrpc_params["name"].to_s
    end

    def jsonrpc_payload
      @jsonrpc_payload ||= begin
        parsed = request_payload
        parsed.is_a?(Hash) ? parsed : {}
      end
    end

    def request_payload
      return @request_payload if defined?(@request_payload)

      body = request.raw_post
      @request_payload =
        if body.blank?
          {}
        else
          JSON.parse(body)
        end
    rescue JSON::ParserError
      @request_payload = request.raw_post
    end
  end
end
