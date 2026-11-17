# frozen_string_literal: true

require "json"
require "securerandom"

module RecordingStudioMcp
  module WebhookDispatch
    MAX_BODY_BYTES = 256 * 1024

    module_function

    def enqueue(event_name:, recording_id:, recording: nil)
      return unless RecordingStudioMcp.configuration.events_enabled
      return unless ready?

      registration = RecordingStudioMcp.configuration.event_catalog.fetch(event_name)
      webhook = registration&.webhook
      return if webhook.nil?

      loaded = recording || find_recording(recording_id)
      return if loaded.nil?
      return unless registration.matches_recording?(loaded)

      subscriptions_for(webhook.name).each do |subscription|
        enqueue_subscription(subscription, webhook, loaded)
      end
    end

    def ready?
      EventSubscription.table_available?
    rescue StandardError
      false
    end

    def subscriptions_for(event_name)
      EventSubscription.active.where(event_name: event_name)
    end

    def enqueue_subscription(subscription, webhook, recording)
      return unless subscription.matches_recording?(recording)

      event_id = "evt_#{SecureRandom.hex(16)}"
      body = serialized_body(webhook: webhook, recording: recording, event_id: event_id)
      if body.bytesize > MAX_BODY_BYTES
        subscription.record_failure!(message: "payload exceeds 256 KiB")
        return
      end

      queue_delivery(
        subscription_id: subscription.id,
        body: body,
        event_id: event_id
      )
    end
    private_class_method :enqueue_subscription

    def queue_delivery(subscription_id:, body:, event_id:)
      DeliverEventWebhookJob.perform_later(
        subscription_id: subscription_id,
        body: body,
        event_id: event_id
      )
    end

    def serialized_body(webhook:, recording:, event_id:)
      JSON.generate(
        {
          "eventId" => event_id,
          "name" => webhook.name,
          "timestamp" => Time.now.utc.iso8601,
          "data" => {
            "recording_id" => recording.id.to_s,
            "uri" => Resources.uri_for(recording)
          },
          "cursor" => nil
        }
      )
    end
    private_class_method :serialized_body

    def delivery_allowed?(subscription:, body:)
      return false if subscription.nil? || !subscription.active?

      recording = recording_from_body(body)
      return false if recording.nil?
      return false unless still_accessible?(subscription, recording)

      true
    end

    def still_accessible?(subscription, recording)
      grant = access_grant_for(subscription)
      return false if grant.nil?
      return false unless Resources.accessible?(grant, Resources.uri_for(recording))
      return false unless live_grant?(grant)

      true
    end

    def live_grant?(grant)
      access_recording = grant.access_recording
      return false if access_recording.nil?
      return access_recording.kept? if access_recording.respond_to?(:kept?)
      return false if access_recording.respond_to?(:trashed_at) && access_recording.trashed_at.present?

      true
    end
    private_class_method :live_grant?

    def recording_from_body(body)
      id = recording_id_from(body)
      return if id.blank?

      RECORDING_REF.new(id)
    end
    private_class_method :recording_from_body

    def recording_id_from(body)
      payload = JSON.parse(body)
      payload.dig("data", "recording_id").presence
    rescue JSON::ParserError, TypeError
      nil
    end
    private_class_method :recording_id_from

    RECORDING_REF = Struct.new(:id)
    private_constant :RECORDING_REF

    def access_grant_for(subscription)
      client = principal_for(subscription)
      access_recording = access_recording_for(subscription)
      return if client.nil? || access_recording.nil?
      return unless defined?(RecordingStudioApi::AccessGrant)

      RecordingStudioApi::AccessGrant.new(
        api_client: client,
        credential: nil,
        access_recording: access_recording,
        root_recording: access_recording.root_recording
      )
    end
    private_class_method :access_grant_for

    def principal_for(subscription)
      id = subscription.owner_principal_id
      oauth_principal(id) || api_client_principal(id)
    end
    private_class_method :principal_for

    def oauth_principal(id)
      return unless defined?(RecordingStudioOauth::OauthClient)

      RecordingStudioOauth::OauthClient.find_by(id: id)
    end
    private_class_method :oauth_principal

    def api_client_principal(id)
      return unless defined?(RecordingStudioApi::ApiClient)

      RecordingStudioApi::ApiClient.find_by(id: id)
    end
    private_class_method :api_client_principal

    def access_recording_for(subscription)
      return unless defined?(RecordingStudio::Recording)
      return if subscription.access_recording_id.blank?

      RecordingStudio::Recording.find_by(id: subscription.access_recording_id)
    end
    private_class_method :access_recording_for

    def find_recording(recording_id)
      return unless defined?(RecordingStudio::Recording)

      RecordingStudio::Recording.find_by(id: recording_id)
    end
    private_class_method :find_recording
  end
end
