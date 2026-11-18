# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def fetch_capability_payload(args)
      stored = read_capability_store(args)
      return if stored.nil?

      payload = stored["json"]
      return payload if capability_payload?(payload)

      raise RecordingStudioApi::InvalidActionInputError, capability_scope_error(nil)
    end

    def read_capability_store(args)
      RecordingStudioApi::IdempotencyStore.fetch(
        api: api_key,
        client_id: grant_idempotency_client_id,
        key: capability_storage_key(capability_client_key(args))
      )
    end

    def capability_payload?(payload)
      payload.is_a?(Hash) && payload.key?("scope") && payload.key?("body")
    end

    def enforce_capability_scope!(payload, call)
      return if payload["scope"] == capability_scope(call)

      raise RecordingStudioApi::InvalidActionInputError, capability_scope_error(payload["scope"])
    end

    def capability_scope(call)
      {
        "action" => call.action.name.to_s,
        "type" => call.recordable_type.to_s,
        "record_id" => call.recording.id.to_s
      }
    end

    def capability_scope_error(scope)
      return "Idempotency key was already used for a different action" unless scope.is_a?(Hash)

      "Idempotency key was already used for #{scope['action']} on #{scope['type']} #{scope['record_id']}"
    end

    def capability_storage_key(client_key)
      "capability:#{client_key}"
    end

    def capability_client_key(args)
      body = stringify_keys(args)
      nested = stringify_keys(body["params"])
      body["idempotency_key"].presence || idempotency_key.presence || nested["idempotency_key"].presence
    end

    def grant_idempotency_client_id
      client = access_grant.api_client
      return client.id if client

      actor = access_grant.actor if access_grant.respond_to?(:actor)
      actor_idempotency_client_id(actor)
    end
  end
end
