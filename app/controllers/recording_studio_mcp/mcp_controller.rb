# frozen_string_literal: true

module RecordingStudioMcp
  class McpController < ActionController::API
    def handle
      auth = Authenticator.access_grant(request.headers["Authorization"])
      unless auth.success?
        error = auth.error == :missing_token ? nil : "invalid_token"
        response.set_header("WWW-Authenticate", WwwAuthenticate.header_value(request, error: error))
        return render json: { error: "unauthorized" }, status: :unauthorized
      end

      return head :method_not_allowed unless request.post?

      result = Protocol.handle(request_payload, access_grant: auth.access_grant)
      return head :accepted if result.notification && result.body.nil?

      render json: result.body, status: result.status
    end

    private

    def request_payload
      body = request.raw_post
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      request.raw_post
    end
  end
end
