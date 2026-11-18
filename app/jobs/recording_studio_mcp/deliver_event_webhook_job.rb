# frozen_string_literal: true

module RecordingStudioMcp
  class DeliverEventWebhookJob < ActiveJob::Base
    queue_as :recording_studio_mcp_events

    retry_on TransientWebhookFailure, wait: :polynomially_longer, attempts: 5

    def perform(subscription_id:, recording_id:, event_id:)
      subscription = EventSubscription.find_by(id: subscription_id)
      return unless WebhookDispatch.delivery_allowed?(subscription: subscription, recording_id: recording_id)

      body = WebhookDispatch.body_for(subscription: subscription, recording_id: recording_id, event_id: event_id)
      return if body.nil?

      WebhookDelivery.call(subscription: subscription, body: body, event_id: event_id)
    end
  end
end
