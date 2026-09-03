# frozen_string_literal: true

module RecordingStudioMcp
  class McpController < ActionController::API
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging

    prepend_before_action :authenticate_mcp!
    include RecordingStudioApi::Concerns::ApiAccessControl

    def handle
      return head :method_not_allowed unless request.post?

      result = Protocol.handle(
        request_payload,
        access_grant: @access_grant,
        idempotency_key: request.headers["Idempotency-Key"].presence
      )
      return head :accepted if result.notification && result.body.nil?

      render json: result.body, status: result.status
    end

    private

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
      return true if %w[initialize ping tools/list].include?(method_name)
      return true if method_name == "tools/call" && %w[list show describe].include?(jsonrpc_tool_name)

      false
    end

    def jsonrpc_method
      jsonrpc_payload["method"].to_s
    end

    def jsonrpc_tool_name
      params = jsonrpc_payload["params"]
      return "" unless params.is_a?(Hash)

      params["name"].to_s
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
