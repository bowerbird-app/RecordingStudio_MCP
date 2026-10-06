# frozen_string_literal: true

module RecordingStudioMcp
  module EventRpc
    CALLBACK_ENDPOINT_ERROR = -32_015
    MIN_TTL = 60

    Error = Data.define(:code, :message, :data)
    Answer = Data.define(:payload)

    module_function

    def list(params:, protocol_version:)
      return Error.new(Protocol::INVALID_PARAMS, "Invalid params", nil) unless params["cursor"].nil?

      events = webhook_events.map { |registration| listed_event(registration) }
      Answer.new(
        ResultShape.complete({ events: events }, protocol_version: protocol_version)
      )
    end

    def subscribe(params:, access_grant:, protocol_version:)
      principal_id = principal_id(access_grant)
      return Error.new(Protocol::INVALID_PARAMS, "not authorized", nil) if principal_id.blank?
      return Error.new(Protocol::INTERNAL_ERROR, "Event subscriptions are not installed", nil) unless table?

      delivery = params["delivery"] || {}
      name = params["name"].to_s
      arguments = params["arguments"] || {}
      registration = RecordingStudioMcp.configuration.event_catalog.fetch_webhook(name)
      return Error.new(Protocol::INVALID_PARAMS, "unknown event", nil) if registration.nil?

      schema_error = JsonObjectSchema.error_for(registration.webhook.arguments_schema, arguments)
      return Error.new(Protocol::INVALID_PARAMS, schema_error, nil) if schema_error

      normalized = CanonicalJson.normalize(arguments)
      return Error.new(Protocol::INVALID_PARAMS, "not authorized", nil) unless authorized?(access_grant, registration,
                                                                                           normalized)

      secret = delivery["secret"]
      return Error.new(Protocol::INVALID_PARAMS, "invalid signing secret", nil) if WebhookSecret.parse(secret).nil?

      unless delivery["mode"].to_s == "webhook"
        return Error.new(Protocol::INVALID_PARAMS, "delivery must be webhook",
                         nil)
      end

      url = delivery["url"].to_s
      CallbackUrl.parse!(url)
      expires_at = granted_expiry(params["ttlMs"])
      id = SubscriptionIdentity.generate(
        principal_id: principal_id,
        callback_url: url,
        event_name: name,
        arguments: normalized
      )
      existing = records.find_by(id: id)
      if existing.nil? && at_cap?(principal_id)
        return Error.new(Protocol::INVALID_PARAMS, "subscription limit reached",
                         nil)
      end

      CallbackVerifier.verify!(principal_id: principal_id, url: url, secret: secret, subscription_id: id)
      record = upsert_subscription(
        existing: existing,
        id: id,
        principal_id: principal_id,
        access_recording_id: access_recording_id(access_grant),
        name: name,
        arguments: normalized,
        url: url,
        secret: secret,
        expires_at: expires_at
      )
      Answer.new(
        ResultShape.complete(
          {
            id: record.id,
            refreshBefore: record.expires_at.utc.iso8601,
            cursor: nil,
            truncated: false
          },
          protocol_version: protocol_version,
          cacheable: false
        )
      )
    rescue CallbackUrl::Error => e
      Error.new(CALLBACK_ENDPOINT_ERROR, "Callback endpoint error", { reason: e.reason.to_s })
    end

    def unsubscribe(params:, access_grant:)
      principal_id = principal_id(access_grant)
      return Error.new(Protocol::INVALID_PARAMS, "not authorized", nil) if principal_id.blank?
      return Answer.new({}) unless table?

      name = params["name"].to_s
      arguments = CanonicalJson.normalize(params["arguments"] || {})
      url = (params["delivery"] || {})["url"].to_s
      id = SubscriptionIdentity.generate(
        principal_id: principal_id,
        callback_url: url,
        event_name: name,
        arguments: arguments
      )
      subscription = records.find_by(id: id)
      subscription&.deactivate!(message: "unsubscribed")
      Answer.new({})
    end

    def webhook_events
      RecordingStudioMcp.configuration.event_catalog.select(&:webhook)
    end
    private_class_method :webhook_events

    def listed_event(registration)
      webhook = registration.webhook
      {
        name: webhook.name,
        description: webhook.description,
        delivery: ["webhook"],
        inputSchema: webhook.arguments_schema,
        payloadSchema: webhook.payload_schema
      }
    end
    private_class_method :listed_event

    def principal_id(access_grant)
      client = access_grant&.api_client
      client&.id&.to_s.presence
    end
    private_class_method :principal_id

    def access_recording_id(access_grant)
      return unless access_grant.respond_to?(:access_recording)

      access_grant.access_recording&.id
    end
    private_class_method :access_recording_id

    def records
      EventSubscription
    end

    def table?
      records.table_available?
    rescue NameError, LoadError
      false
    end
    private_class_method :table?

    def authorized?(access_grant, registration, arguments)
      recording_id = arguments["recording_id"].to_s
      recording = Resources.find_accessible(access_grant, recording_id)
      return false if recording.nil?

      registration.matches_recording?(recording)
    end
    private_class_method :authorized?

    def granted_expiry(ttl_ms)
      default = duration_seconds(RecordingStudioMcp.configuration.event_subscription_ttl)
      requested = ttl_seconds(ttl_ms)
      granted = requested ? [requested, default].min : default
      granted = MIN_TTL if granted < MIN_TTL
      Time.now.utc + granted
    end
    private_class_method :granted_expiry

    def ttl_seconds(ttl_ms)
      return nil if ttl_ms.nil?
      return nil unless ttl_ms.is_a?(Integer) && ttl_ms.positive?

      ttl_ms / 1000
    end
    private_class_method :ttl_seconds

    def duration_seconds(value)
      return value.to_i if value.respond_to?(:to_i)

      24.hours.to_i
    end
    private_class_method :duration_seconds

    def at_cap?(principal_id)
      cap = RecordingStudioMcp.configuration.event_subscriptions_per_principal.to_i
      records.where(owner_principal_id: principal_id, status: "active").count >= cap
    end
    private_class_method :at_cap?

    def upsert_subscription(existing:, id:, principal_id:, access_recording_id:, name:, arguments:, url:, secret:,
                            expires_at:)
      if existing
        existing.refresh!(secret: secret, expires_at: expires_at, access_recording_id: access_recording_id)
        existing
      else
        records.create!(
          id: id,
          owner_principal_id: principal_id,
          access_recording_id: access_recording_id,
          event_name: name,
          arguments: arguments,
          callback_url: url,
          callback_secret: secret,
          status: "active",
          expires_at: expires_at
        )
      end
    end
    private_class_method :upsert_subscription
  end
end
