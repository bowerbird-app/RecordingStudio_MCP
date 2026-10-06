# frozen_string_literal: true

require "json"
require "securerandom"

module RecordingStudioMcp
  module CallbackVerifier
    CACHE_TTL = 1.hour
    ChallengeFailed = Class.new(CallbackUrl::Error)

    module_function

    def verify!(principal_id:, url:, secret:, subscription_id:)
      return if cached?(principal_id, url)

      challenge = SecureRandom.hex(16)
      event_id = "msg_verification_#{SecureRandom.hex(12)}"
      body = JSON.generate({ "type" => "verification", "challenge" => challenge })
      response = signed_post(url: url, secret: secret, subscription_id: subscription_id, event_id: event_id, body: body)
      raise ChallengeFailed.new(:challenge_failed, "callback did not echo the challenge") unless echoed?(response,
                                                                                                         challenge)

      cache!(principal_id, url)
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ETIMEDOUT, Errno::ECONNREFUSED
      raise CallbackUrl::Error.new(:timeout, "callback timed out")
    end

    def reset_cache!
      cache.clear
    end

    def signed_post(url:, secret:, subscription_id:, event_id:, body:)
      timestamp = Time.now.to_i
      CallbackHttp.post(
        url,
        body: body,
        headers: {
          "Content-Type" => "application/json",
          "webhook-id" => event_id,
          "webhook-timestamp" => timestamp.to_s,
          "webhook-signature" => WebhookSignature.header(
            id: event_id,
            timestamp: timestamp,
            body: body,
            secret: secret
          ),
          "X-MCP-Subscription-Id" => subscription_id
        }
      )
    end
    private_class_method :signed_post

    def echoed?(response, challenge)
      return false unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body.to_s)
      returned = payload["challenge"].to_s
      return false if returned.blank?

      ActiveSupport::SecurityUtils.secure_compare(returned, challenge)
    rescue JSON::ParserError, TypeError
      false
    end
    private_class_method :echoed?

    def cached?(principal_id, url)
      expires_at = cache[[principal_id.to_s, url.to_s]]
      expires_at.present? && expires_at > Time.now
    end
    private_class_method :cached?

    def cache!(principal_id, url)
      cache[[principal_id.to_s, url.to_s]] = CACHE_TTL.from_now
    end
    private_class_method :cache!

    def cache
      @cache ||= {}
    end
    private_class_method :cache
  end
end
