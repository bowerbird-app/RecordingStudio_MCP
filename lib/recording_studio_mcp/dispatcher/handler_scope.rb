# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    HANDLER_SCOPE_MISS = "Resource was not found in this API scope"
    HANDLER_SCOPE_ERRORS = [
      RecordingStudioApi::NotFoundError,
      RecordingStudioApi::AuthorizationError
    ].freeze

    private

    # The guard result, or nil when the id is out of scope.
    # NotFoundError and AuthorizationError become one tool error. The guard
    # message is dropped so a missing id and a role failure look the same.
    def handler_scope
      yield
    rescue *HANDLER_SCOPE_ERRORS
      nil
    end

    def scope_miss_result
      error_result(HANDLER_SCOPE_MISS)
    end

    def scoped_resource(recordable_type, operation_name, id)
      handler_scope do
        RecordingStudioApi::HandlerGuard.resource!(**resource_guard_args(recordable_type, operation_name, id))
      end
    end

    def guarded_resource_context(recordable_type, args, guarded, operation_name)
      resource_context(
        recordable_type,
        args,
        recording: guarded.recording,
        parent_recording: guarded.parent_recording,
        operation_name: operation_name
      )
    end

    def resource_guard_args(recordable_type, operation_name, id)
      {
        access_grant: access_grant,
        recordable_type: recordable_type,
        action_name: operation_name,
        id: id,
        registration: resource_registration_for(recordable_type, operation_name)
      }
    end

    def capability_guard(recordable_type, action, args)
      RecordingStudioApi::HandlerGuard.capability!(**capability_guard_args(recordable_type, action, args))
    end

    def capability_guard_args(recordable_type, action, args)
      {
        access_grant: access_grant,
        api_client: access_grant.api_client,
        recordable_type: recordable_type,
        action: action,
        id: args["id"],
        registration: resource_handler_registration(recordable_type, action.name)
      }
    end

    def capability_context(recording, args, action, recordable_type)
      enabled_capability_action!(recordable_type, action.name.to_s)
      action_context(recording, args, action, recordable_type: recordable_type)
    end

    def resource_handler_registration(recordable_type, action_name)
      RecordingStudioApi.resource_handler_registration(recordable_type, action_name, api: api_key)
    end

    def resource_registration_for(recordable_type, action_name)
      resource_handler_registration(recordable_type, action_name) || default_resource_registration
    end

    def default_resource_registration
      RecordingStudioApi::ResourceHandlerRegistration.new(
        handler: nil,
        include_trashed: false,
        owns_scoping: false,
        trashed_semantics: nil
      )
    end
  end
end
