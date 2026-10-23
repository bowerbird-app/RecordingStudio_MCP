# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def dispatch_tree(name, args)
      case name
      when "describe"
        success_result(catalog.describe(args["type"]))
      when "capability_action"
        dispatch_capability_action(args)
      else
        dispatch_resource(RESOURCE_TOOLS.fetch(name), args)
      end
    end

    def dispatch_resource(operation_name, args)
      validate_index_arguments!(args) if operation_name == :index
      recordable_type = catalog.resolve_type!(args["type"])
      reject_disabled_operation!(recordable_type, operation_name)
      handler = resource_handler(recordable_type, operation_name)
      return call_resource_handler(recordable_type, operation_name, args) if handler

      call_builtin_resource(recordable_type, operation_name, args)
    end

    def reject_disabled_operation!(recordable_type, operation_name)
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
      return unless registration && !registration.supports_operation?(operation_name)

      raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{recordable_type}"
    end

    def resource_handler(recordable_type, operation_name)
      RecordingStudioApi.resource_handler(recordable_type, operation_name, api: api_key)
    end

    def call_resource_handler(recordable_type, operation_name, args)
      handler = resource_handler(recordable_type, operation_name)
      context = resource_context(recordable_type, args, recording: nil, operation_name: operation_name)
      render_handler_result(handler.call(context))
    end

    def call_builtin_resource(recordable_type, operation_name, args)
      operation = RecordingStudioApi.resource_action(operation_name, version: api_version, api: api_key)
      if operation.nil?
        raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}"
      end

      recording = builtin_member_recording_for(operation_name, recordable_type, args["id"])
      context = resource_context(recordable_type, args, recording: recording, operation_name: operation_name)
      success_result(operation.handler.call(context).fetch(:json))
    end

    def dispatch_capability_action(args)
      recordable_type = catalog.resolve_type!(args["type"])
      action = enabled_capability_action!(recordable_type, args["action"].to_s)
      handler = resource_handler(recordable_type, action.name)
      return call_capability_handler(handler, args, action, recordable_type) if handler

      run_capability_action(recordable_type, args, action)
    end

    def enabled_capability_action!(recordable_type, action_name)
      raise RecordingStudioApi::InvalidActionInputError, "action is required" if action_name.blank?

      action = RecordingStudioApi.capability_action(action_name, version: api_version, api: api_key)
      enabled = action && RecordingStudioApi.capability_action_enabled_for?(action, recordable_type, api: api_key)
      return action if enabled

      raise RecordingStudioApi::UnsupportedActionError, catalog.unknown_action_message(action_name, recordable_type)
    end

    def call_capability_handler(handler, args, action, recordable_type)
      render_handler_result(handler.call(action_context(nil, args, action, recordable_type: recordable_type)))
    end

    def run_capability_action(recordable_type, args, action)
      recording = load_recording(recordable_type, args["id"])
      authorize_capability!(recording, action)
      payload = serialize_capability_result(action, action.handler.call(action_context(recording, args, action)))
      success_result(payload)
    end

    def authorize_capability!(recording, action)
      required_role = RecordingStudioApi.configuration.capability_action_role_for(
        action: action,
        recording: recording,
        api_client: access_grant.api_client,
        access_grant: access_grant
      )
      access_grant.authorize!(recording: recording, role: required_role) if required_role.present?
    end

    def builtin_member_recording_for(operation_name, recordable_type, id)
      case operation_name
      when :show, :update then load_recording(recordable_type, id)
      when :destroy then load_recording(recordable_type, id, include_trashed: true)
      end
    end
  end
end
