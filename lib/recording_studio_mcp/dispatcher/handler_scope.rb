# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    HANDLER_SCOPE_MISS = "Resource was not found in this API scope"

    private

    # tools/list includes every tool this server includes. A missing or
    # out-of-scope id stays HANDLER_SCOPE_MISS. AuthorizationError is a tool
    # error with the Recording Studio API message so an over-role call is
    # refused clearly, not as not found.
    def handler_scope
      yield
    rescue RecordingStudioApi::NotFoundError
      nil
    end

    def scope_miss_result(expected_type: nil, id: nil, operation: nil)
      error_result(handler_scope_message(expected_type, id, operation))
    end

    def handler_scope_message(expected_type, id, operation)
      recording = mismatched_recording(expected_type, id)
      return HANDLER_SCOPE_MISS if recording.nil?

      actual = catalog.displayed_type_name(recording.recordable_type)
      expected = catalog.displayed_type_name(expected_type)
      tool = sibling_tool_name(recording.recordable_type, operation)
      lead = "Resource type does not match #{expected}. This id is a #{actual}."
      return "#{lead} Use #{tool}." if tool

      "#{lead} Use that item's content_id."
    end

    def mismatched_recording(expected_type, id)
      return if expected_type.blank? || id.blank?

      recording = scoped_recordings(false).find_by(id: id)
      return if recording.nil?

      found = recording.recordable_type.to_s
      return if found == expected_type.to_s
      return unless catalog.type_names.include?(found)

      recording
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

    def capability_context(recording, args, action, recordable_type, named_tool: false)
      enabled_capability_action!(recordable_type, action.name.to_s)
      action_context(recording, args, action, recordable_type: recordable_type, named_tool: named_tool)
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
        trashed_semantics: nil,
        creates: false
      )
    end
  end
end
