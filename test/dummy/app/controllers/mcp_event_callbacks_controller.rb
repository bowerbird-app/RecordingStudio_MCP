# frozen_string_literal: true

class McpEventCallbacksController < ActionController::API
  def create
    raw = request.raw_post
    payload = JSON.parse(raw)
    if payload["type"] == "verification"
      render json: { challenge: payload["challenge"] }
      return
    end

    subscription = RecordingStudioMcp::EventSubscription.find_by(id: request.headers["X-MCP-Subscription-Id"])
    verified = subscription.present? && RecordingStudioMcp::WebhookSignature.valid?(
      id: request.headers["webhook-id"],
      timestamp: request.headers["webhook-timestamp"],
      body: raw,
      secret: subscription.callback_secret,
      header: request.headers["webhook-signature"]
    )
    Dummy::McpEventInbox.record(
      headers: request.headers.to_h,
      body: payload,
      verified: verified
    )
    return head :unauthorized unless verified

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
