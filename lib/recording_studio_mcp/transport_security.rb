# frozen_string_literal: true

module RecordingStudioMcp
  module TransportSecurity
    extend ActiveSupport::Concern

    included do
      prepend_before_action :validate_origin!, :validate_protocol_version!
    end

    private

    def validate_origin!
      return if OriginGuard.allowed?(
        request.headers["Origin"],
        request_origin: request.base_url,
        allowed_origins: RecordingStudioMcp.configuration.allowed_origins
      )

      render json: { error: "invalid_origin" }, status: :forbidden
    end

    def effective_protocol_version
      header_protocol_version || meta_protocol_version || "2025-03-26"
    end

    def validate_protocol_version!
      return if jsonrpc_method == "initialize"

      header = header_protocol_version
      meta = meta_protocol_version
      return render_header_mismatch(header, meta) if header && meta && header != meta

      version = effective_protocol_version
      return if Configuration::SUPPORTED_PROTOCOL_VERSIONS.include?(version)

      render_unsupported_protocol_version
    end

    def render_header_mismatch(header, meta)
      render json: {
        jsonrpc: Protocol::JSONRPC_VERSION,
        id: jsonrpc_payload["id"],
        error: {
          code: Protocol::HEADER_MISMATCH,
          message: "Header mismatch: MCP-Protocol-Version header value '#{header}' does not match " \
                   "body value '#{meta}'"
        }
      }, status: :bad_request
    end

    def render_unsupported_protocol_version
      render json: api_error_payload(
        code: "unsupported_protocol_version",
        message: "MCP-Protocol-Version is not supported",
        details: { supported_versions: Configuration::SUPPORTED_PROTOCOL_VERSIONS }
      ), status: :bad_request
    end

    def header_protocol_version
      request.headers["MCP-Protocol-Version"].presence
    end

    def meta_protocol_version
      jsonrpc_params.dig("_meta", "io.modelcontextprotocol/protocolVersion").presence
    end
  end
end
