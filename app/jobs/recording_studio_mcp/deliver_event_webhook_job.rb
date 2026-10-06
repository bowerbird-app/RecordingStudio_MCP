# frozen_string_literal: true

module RecordingStudioMcp
  class DeliverEventWebhookJob < ActiveJob::Base
    queue_as :recording_studio_mcp_events

    retry_on TransientWebhookFailure, wait: :polynomially_longer, attempts: 5

    def perform(subscription_id:, body:, event_id:)
      subscription = EventSubscription.find_by(id: subscription_id)
      WebhookDelivery.call(subscription: subscription, body: body, event_id: event_id)
    end
  end
end
