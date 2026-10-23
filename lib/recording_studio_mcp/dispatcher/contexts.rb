# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def resource_context(recordable_type, args, recording: nil, operation_name: nil)
      fields = resource_context_fields(recordable_type, args, recording, operation_name)
      RecordingStudioApi::ResourceOperationContext.new(**fields)
    end

    def resource_context_fields(recordable_type, args, recording, operation_name)
      grant_fields
        .merge(resource_identity_fields(recordable_type, args, recording))
        .merge(resource_request_fields(recordable_type, args, operation_name))
    end

    def resource_identity_fields(recordable_type, args, recording)
      {
        recording: recording,
        recordable_type: recordable_type,
        resource_name: RecordingStudioApi.resource_name_for(recordable_type),
        id: args["id"],
        parent_id: args["parent_id"],
        parent_recording: nil,
        relationship_id: nil
      }
    end

    def resource_request_fields(recordable_type, args, operation_name)
      {
        api_version: api_version,
        params: permitted_params(resource_params(recordable_type, args)),
        request_params: permitted_params(write_params(recordable_type, args, operation_name)),
        scoped_recordings: access_grant.accessible_recordings,
        idempotency_key: create_idempotency_key(args, operation_name),
        progress_reporter: progress_reporter
      }
    end

    def action_context(recording, args, action, recordable_type: nil)
      RecordingStudioApi::ActionContext.new(
        **grant_fields,
        recording: recording,
        params: capability_input_params(args, action),
        progress_reporter: progress_reporter,
        id: args["id"],
        recordable_type: recordable_type
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

    def resource_params(recordable_type, args)
      keys = %w[id q limit sort order filter include pagination_token]
      { "resource" => RecordingStudioApi.resource_name_for(recordable_type) }.merge(args.slice(*keys)).compact
    end

    def write_params(recordable_type, args, operation_name)
      return {} unless %i[create update].include?(operation_name)

      reject_attributes_wrapper!(args)
      payload = stringify_keys(args).except(*WRITE_RESERVED_KEYS)
      reject_unknown_fields!(recordable_type, payload)
      payload["parent_id"] = args["parent_id"] if args.key?("parent_id")
      payload
    end

    def reject_attributes_wrapper!(args)
      return unless args.key?("attributes")

      raise RecordingStudioApi::InvalidActionInputError,
            "Send writable fields at the request root, not inside attributes"
    end

    def reject_unknown_fields!(recordable_type, payload)
      allowed = catalog.writable_fields(recordable_type)
      unknown = payload.keys - allowed
      return if unknown.empty?

      allowed_sentence = allowed.any? ? allowed.join(", ") : "(none)"
      raise RecordingStudioApi::InvalidActionInputError,
            "Unknown fields #{unknown.sort.join(', ')}. Writable fields for #{recordable_type}: #{allowed_sentence}"
    end

    def create_idempotency_key(args, operation_name)
      return unless operation_name == :create

      args["idempotency_key"].presence || idempotency_key
    end

    def capability_input_params(args, action)
      raw = stringify_keys(args["params"]).presence || {}
      normalized = raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw
      return normalized if action.input_contract.nil?

      contract_result = action.input_contract.call(normalized)
      unless contract_result.success?
        raise RecordingStudioApi::InvalidActionInputError, "Invalid input for action #{action.name}"
      end

      contract_result.value
    end
  end
end
