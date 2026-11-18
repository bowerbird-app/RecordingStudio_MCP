# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def replayed_create(context, operation_name)
      return unless operation_name == :create

      stored = idempotent_create(context)
      stored if stored.present?
    end

    def store_create(context, operation_name, result)
      return unless store_create?(context, operation_name, result)

      status = result.fetch(:status, :ok)
      RecordingStudioApi::IdempotencyStore.write(
        api: context.api_key,
        client_id: idempotency_client_id(context),
        key: context.idempotency_key,
        payload: result.fetch(:json),
        status: status.to_s
      )
    end

    def store_create?(context, operation_name, result)
      operation_name == :create && result.is_a?(Hash) && context.idempotency_key.present? &&
        successful_status?(result.fetch(:status, :ok))
    end

    def idempotent_create(context)
      key = context.idempotency_key
      return if key.blank?

      RecordingStudioApi::IdempotencyStore.fetch(
        api: context.api_key,
        client_id: idempotency_client_id(context),
        key: key
      )
    end

    def idempotency_client_id(context)
      client = context.api_client
      return client.id if client

      actor_idempotency_client_id(context.actor)
    end

    def actor_idempotency_client_id(actor)
      return if actor.blank?

      type_name = actor.class.respond_to?(:polymorphic_name) ? actor.class.polymorphic_name : actor.class.name
      identifier = actor.id if actor.respond_to?(:id)
      return if type_name.blank? || identifier.blank?

      "actor:#{type_name}:#{identifier}"
    end

    def successful_status?(status)
      SUCCESS_STATUS_RANGE.cover?(Rack::Utils.status_code(status))
    end
  end
end
