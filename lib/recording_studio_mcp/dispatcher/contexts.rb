# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    include FieldErrors

    private

    def resource_context(recordable_type, args, recording: nil, parent_recording: nil, operation_name: nil)
      fields = resource_context_fields(recordable_type, args, recording, parent_recording, operation_name)
      RecordingStudioApi::ResourceOperationContext.new(**fields)
    end

    def resource_context_fields(recordable_type, args, recording, parent_recording, operation_name)
      grant_fields
        .merge(resource_identity_fields(recordable_type, args, recording, parent_recording, operation_name))
        .merge(resource_request_fields(recordable_type, args, operation_name))
    end

    def resource_identity_fields(recordable_type, args, recording, parent_recording, operation_name)
      {
        recording: recording,
        recordable_type: recordable_type,
        resource_name: RecordingStudioApi.resource_name_for(recordable_type),
        id: args["id"],
        parent_id: (server_chosen_create?(recordable_type, operation_name) ? nil : args["parent_id"]),
        parent_recording: parent_recording,
        relationship_id: nil
      }
    end

    def server_chosen_create?(recordable_type, operation_name)
      operation_name == :create &&
        catalog.respond_to?(:server_chosen_create_parent?) &&
        catalog.server_chosen_create_parent?(recordable_type)
    end

    def resource_request_fields(recordable_type, args, operation_name)
      {
        api_version: api_version,
        params: permitted_params(resource_params(recordable_type, args, operation_name)),
        request_params: permitted_params(write_params(recordable_type, args, operation_name)),
        scoped_recordings: access_grant.accessible_recordings,
        idempotency_key: create_idempotency_key(args, operation_name),
        progress_reporter: progress_reporter
      }
    end

    def action_context(recording, args, action, recordable_type: nil, named_tool: false)
      RecordingStudioApi::ActionContext.new(
        **grant_fields,
        recording: recording,
        params: capability_input_params(args, action, named_tool: named_tool),
        progress_reporter: progress_reporter,
        id: args["id"],
        recordable_type: recordable_type,
        idempotency_key: capability_idempotency_key(args)
      )
    end

    def grant_fields
      {
        api_client: access_grant.api_client,
        credential: access_grant.credential,
        access_recording: access_grant.access_recording,
        access_grant: access_grant,
        root_recording: access_grant.root_recording
      }
    end

    def permitted_params(hash)
      ActionController::Parameters.new(hash).permit!
    end

    def resource_params(recordable_type, args, operation_name)
      keys = %w[id parent_id q limit sort order filter include pagination_token]
      sliced = args.slice(*keys)
      sliced = sliced.except("parent_id") if server_chosen_create?(recordable_type, operation_name)
      { "resource" => RecordingStudioApi.resource_name_for(recordable_type) }.merge(sliced).compact
    end

    def write_params(recordable_type, args, operation_name)
      return {} unless %i[create update].include?(operation_name)

      reject_attributes_wrapper!(args)
      payload = stringify_keys(args).except(*WRITE_RESERVED_KEYS, *FINGERPRINT_EXCLUDED_KEYS)
      reject_unknown_fields!(recordable_type, payload, operation_name)
      if args.key?("parent_id") && !server_chosen_create?(recordable_type, operation_name)
        payload["parent_id"] = args["parent_id"]
      end
      payload
    end

    def reject_attributes_wrapper!(args)
      return unless args.key?("attributes")

      raise RecordingStudioApi::InvalidActionInputError,
            "Send writable fields at the request root, not inside attributes"
    end

    def reject_unknown_fields!(recordable_type, payload, operation_name)
      allowed = catalog.writable_fields(recordable_type, operation: operation_name)
      reject_immutable_update_fields!(recordable_type, payload, allowed)
      unknown = payload.keys - allowed
      return if unknown.empty?

      raise RecordingStudioApi::InvalidActionInputError, unknown_fields_message(recordable_type, unknown, allowed)
    end

    def create_idempotency_key(args, operation_name)
      return unless operation_name == :create

      args["idempotency_key"].presence || idempotency_key
    end

    def capability_idempotency_key(args)
      body = stringify_keys(args)
      nested = stringify_keys(body["params"])
      body["idempotency_key"].presence || idempotency_key.presence || nested["idempotency_key"].presence
    end
  end
end
