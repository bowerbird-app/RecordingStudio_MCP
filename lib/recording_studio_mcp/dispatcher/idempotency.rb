# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def replay_registered_create(context, operation_name, &block)
      return block.call unless operation_name == :create

      replay_with(
        context,
        key: context.idempotency_key,
        fingerprint: create_request_fingerprint(context),
        &block
      )
    end

    def replay_creating_action(action, recordable_type, context, &block)
      return block.call unless creating_action?(action, recordable_type)

      replay_with(
        context,
        key: context.idempotency_key,
        action: action.name,
        recording_id: context.recording&.id || context.id,
        input: context.params,
        fingerprint: capability_request_fingerprint(action, recordable_type, context),
        &block
      )
    end

    def creating_action?(action, recordable_type)
      return true if action.creates?

      resource_handler_registration(recordable_type, action.name)&.creates?
    end

    def replay_with(context, key:, fingerprint: nil, **scope, &block)
      return block.call if key.blank?

      RecordingStudioApi::Idempotency.replay(
        api: context.api_key,
        client_id: replay_client_id(context),
        key: key,
        fingerprint: fingerprint,
        **scope,
        &block
      )
    end

    def replay_client_id(context)
      RecordingStudioApi::Idempotency.client_id(
        api_client: context.api_client,
        actor: context.actor
      )
    end

    def create_request_fingerprint(context)
      RecordingStudioApi::IdempotencyStore.fingerprint(
        method: "POST",
        path: create_fingerprint_path(context),
        params: fingerprint_body(context.request_params)
      )
    end

    def capability_request_fingerprint(action, recordable_type, context)
      identifier = context.recording&.id || context.id
      RecordingStudioApi::IdempotencyStore.fingerprint(
        method: capability_http_method(action),
        path: "#{catalog.displayed_type_name(recordable_type)}/#{identifier}/#{action.name}",
        params: fingerprint_body(context.params)
      )
    end

    def capability_http_method(action)
      verb = action.http_verb if action.respond_to?(:http_verb)
      verb.presence || "POST"
    end

    def create_fingerprint_path(context)
      parent = context.parent_recording
      name = context.resource_name.to_s
      parent.present? ? "#{name}/#{parent.id}" : name
    end

    def fingerprint_body(params)
      source = if params.respond_to?(:to_unsafe_h)
                 params.to_unsafe_h
               elsif params.respond_to?(:to_h)
                 params.to_h
               else
                 {}
               end
      source.stringify_keys.except(*FINGERPRINT_EXCLUDED_KEYS)
    end
  end
end
