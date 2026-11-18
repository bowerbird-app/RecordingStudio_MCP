# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def replay_registered_create(context, operation_name, &block)
      return block.call unless operation_name == :create

      replay_with(context, key: context.idempotency_key, &block)
    end

    def replay_creating_action(action, recordable_type, context, &block)
      return block.call unless creating_action?(action, recordable_type)

      replay_with(
        context,
        key: context.idempotency_key,
        action: action.name,
        recording_id: context.recording&.id || context.id,
        input: context.params,
        &block
      )
    end

    def creating_action?(action, recordable_type)
      return true if action.creates?

      resource_handler_registration(recordable_type, action.name)&.creates?
    end

    def replay_with(context, key:, **scope, &block)
      return block.call if key.blank?

      RecordingStudioApi::Idempotency.replay(
        api: context.api_key,
        client_id: replay_client_id(context),
        key: key,
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
  end
end
