# frozen_string_literal: true

module RecordingStudioMcp
  USAGE_SUBJECT_LIMIT = 255

  UsageCall = Data.define(
    :request_payload,
    :response_body,
    :status,
    :duration_ms,
    :rate_limited,
    :api_client_id
  ) do
    def attributes
      payload = hash_payload
      method_name = payload["method"].to_s.presence || "unknown"
      stored_fields(method_name, payload)
    end

    private

    def hash_payload
      request_payload.is_a?(Hash) ? request_payload : {}
    end

    def stored_fields(method_name, payload)
      {
        method_name: method_name,
        subject_name: subject_name(method_name, payload["params"]),
        status_code: Rack::Utils.status_code(status),
        duration_ms: duration_ms.to_i,
        rate_limited: rate_limited == true,
        failed: failed?,
        api_client_id: api_client_id
      }
    end

    def subject_name(method_name, params)
      params = {} unless params.is_a?(Hash)
      raw = case method_name
            when "tools/call"
              params["name"]
            when "skills/get", "resources/read", "resources/subscribe", "resources/unsubscribe",
                 "resources/templates/list"
              Skills::SkillName.from_uri(params["uri"]) || params["uri"]
            when "subscriptions/listen"
              "listen"
            end
      raw.to_s.first(USAGE_SUBJECT_LIMIT)
    end

    def failed?
      return true if rate_limited == true
      return true if Rack::Utils.status_code(status) >= 400
      return false unless response_body.is_a?(Hash)
      return true if response_body["error"].present?

      response_body.dig("result", "isError") == true
    end
  end
  private_constant :USAGE_SUBJECT_LIMIT
end
