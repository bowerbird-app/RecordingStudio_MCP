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

    def validate_protocol_version!
      return if jsonrpc_method == "initialize"

      version = request.headers["MCP-Protocol-Version"].presence || "2025-03-26"
      return if Configuration::SUPPORTED_PROTOCOL_VERSIONS.include?(version)

      render json: api_error_payload(
        code: "unsupported_protocol_version",
        message: "MCP-Protocol-Version is not supported",
        details: { supported_versions: Configuration::SUPPORTED_PROTOCOL_VERSIONS }
      ), status: :bad_request
    end
  end
end
