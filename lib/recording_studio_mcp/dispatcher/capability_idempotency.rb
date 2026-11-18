# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    CapabilityCall = Data.define(:action, :recordable_type, :recording, :args)

    private

    def call_capability_handler(handler, args, action, recordable_type)
      guarded = handler_scope { capability_guard(recordable_type, action, args) }
      return scope_miss_result unless guarded

      call = capability_call(action, recordable_type, guarded.recording, args)
      replayed_capability(call) || finish_capability_handler(handler, call, args, action, recordable_type)
    end

    def finish_capability_handler(handler, call, args, action, recordable_type)
      context = capability_context(call.recording, args, action, recordable_type)
      result = handler.call(context)
      remember_capability_handler(call, result)
      render_handler_result(result)
    end

    def run_capability_action(recordable_type, args, action)
      recording = authorized_capability_recording(recordable_type, args, action)
      call = capability_call(action, recordable_type, recording, args)
      replayed_capability(call) || finish_capability_action(call, recording, args, action)
    end

    def authorized_capability_recording(recordable_type, args, action)
      recording = load_recording(recordable_type, args["id"])
      authorize_capability!(recording, action)
      recording
    end

    def finish_capability_action(call, recording, args, action)
      called = action.handler.call(action_context(recording, args, action))
      payload = serialize_capability_result(action, called, args)
      remember_capability(call, payload)
      success_result(payload)
    end

    def capability_call(action, recordable_type, recording, args)
      CapabilityCall.new(action:, recordable_type:, recording:, args:)
    end

    def replayed_capability(call)
      return unless capability_replay?(call)

      payload = fetch_capability_payload(call.args)
      return if payload.nil?

      enforce_capability_scope!(payload, call)
      success_result(payload.fetch("body"))
    end

    def remember_capability(call, body, status: :ok)
      return unless capability_replay?(call) && successful_status?(status)

      write_capability(call, body, status)
    end

    def remember_capability_handler(call, result)
      return unless result.is_a?(Hash)

      remember_capability(call, result.fetch(:json), status: result.fetch(:status, :ok))
    end

    def write_capability(call, body, status)
      RecordingStudioApi::IdempotencyStore.write(**capability_write(call, body, status))
    end

    def capability_write(call, body, status)
      {
        api: api_key,
        client_id: grant_idempotency_client_id,
        key: capability_storage_key(capability_client_key(call.args)),
        payload: { "scope" => capability_scope(call), "body" => body },
        status: status.to_s
      }
    end

    def capability_replay?(call)
      call.recording.present? && capability_client_key(call.args).present? && !read_capability?(call.action)
    end

    def read_capability?(action)
      action.respond_to?(:read_action?) && action.read_action?
    end
  end
end
