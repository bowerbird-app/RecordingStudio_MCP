# frozen_string_literal: true

require "net/http"

module RecordingStudioMcp
  class TransientWebhookFailure < StandardError; end

  module WebhookDelivery
    module_function

    def call(subscription:, body:, event_id:)
      return if subscription.nil? || !subscription.active?

      if body.bytesize > WebhookDispatch::MAX_BODY_BYTES
        subscription.record_failure!(message: "payload exceeds 256 KiB")
        return
      end

      response = post(subscription, body: body, event_id: event_id)
      handle_response(subscription, response)
    rescue CallbackUrl::Error => e
      fail_delivery(subscription, e.message, retryable: retryable_reason?(e.reason))
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT, Errno::ECONNREFUSED => e
      fail_delivery(subscription, e.message, retryable: true)
    end

    def post(subscription, body:, event_id:)
      timestamp = Time.now.to_i
      CallbackHttp.post(
        subscription.callback_url,
        body: body,
        headers: {
          "Content-Type" => "application/json",
          "webhook-id" => event_id,
          "webhook-timestamp" => timestamp.to_s,
          "webhook-signature" => WebhookSignature.header(
            id: event_id,
            timestamp: timestamp,
            body: body,
            secret: subscription.callback_secret
          ),
          "X-MCP-Subscription-Id" => subscription.id
        }
      )
    end
    private_class_method :post

    def handle_response(subscription, response)
      status = response.code.to_i
      if response.is_a?(Net::HTTPSuccess)
        subscription.mark_delivered!
        return
      end
      if status == 410
        subscription.deactivate!(message: "410")
        return
      end
      if status == 413
        subscription.record_failure!(message: "413")
        return
      end

      fail_delivery(subscription, "HTTP #{status}", retryable: status >= 500 || status == 429)
    end
    private_class_method :handle_response

    def fail_delivery(subscription, message, retryable:)
      return if subscription.nil?

      subscription.record_failure!(message: message, inactive: !retryable)
      raise TransientWebhookFailure, message if retryable && subscription.reload.active?
    end
    private_class_method :fail_delivery

    def retryable_reason?(reason)
      !%i[private_address redirect invalid_url host_not_allowed].include?(reason)
    end
    private_class_method :retryable_reason?
  end
end
