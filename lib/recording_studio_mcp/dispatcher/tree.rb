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
      lookup = RecordingStudioApi.lookup(api: api_key, recordable_type: recordable_type, operation: operation_name)
      if lookup.nil?
        raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}"
      end

      handler = lookup.handler
      if RecordingStudioApi.resource_handler(recordable_type, operation_name, api: api_key)
        return call_resource_handler(handler, recordable_type, operation_name, args)
      end

      call_builtin_resource(recordable_type, operation_name, args, handler: handler)
    end

    def reject_disabled_operation!(recordable_type, operation_name)
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
      return unless registration && !registration.supports_operation?(operation_name)

      shown = catalog.displayed_type_name(recordable_type)
      raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{shown}"
    end

    def resource_handler(recordable_type, operation_name)
      RecordingStudioApi.lookup(api: api_key, recordable_type: recordable_type, operation: operation_name)&.handler
    end

    def call_resource_handler(handler, recordable_type, operation_name, args)
      guarded = scoped_resource(recordable_type, operation_name, args["id"])
      return scope_miss_result unless guarded

      context = guarded_resource_context(recordable_type, args, guarded, operation_name)
      result = replay_registered_create(context, operation_name) { handler.call(context) }
      render_handler_result(result)
    end

    def call_builtin_resource(recordable_type, operation_name, args, handler:)
      recording = builtin_member_recording_for(operation_name, recordable_type, args["id"])
      context = resource_context(recordable_type, args, recording: recording, operation_name: operation_name)
      success_result(handler.call(context).fetch(:json))
    end

    def dispatch_capability_action(args)
      recordable_type = catalog.resolve_type!(args["type"])
      action = enabled_capability_action!(recordable_type, args["action"].to_s)
      lookup = RecordingStudioApi.lookup(
        api: api_key,
        recordable_type: recordable_type,
        action: action.name
      )
      handler = lookup&.handler
      if RecordingStudioApi.resource_handler(recordable_type, action.name, api: api_key)
        return call_capability_handler(handler, args, action, recordable_type)
      end

      run_capability_action(recordable_type, args, action, handler: handler)
    end

    def call_capability_handler(handler, args, action, recordable_type)
      guarded = handler_scope { capability_guard(recordable_type, action, args) }
      return scope_miss_result unless guarded

      context = capability_context(guarded.recording, args, action, recordable_type)
      result = replay_creating_action(action, recordable_type, context) { handler.call(context) }
      render_handler_result(result)
    end

    def run_capability_action(recordable_type, args, action, handler: nil)
      recording = load_recording(recordable_type, args["id"])
      authorize_capability!(recording, action)
      context = action_context(recording, args, action)
      action_handler = handler || action.handler
      result = replay_creating_action(action, recordable_type, context) do
        called = action_handler.call(context)
        { json: serialize_capability_result(action, called, args), status: :ok }
      end
      success_result(result.fetch(:json))
    end

    def enabled_capability_action!(recordable_type, action_name)
      raise RecordingStudioApi::InvalidActionInputError, "action is required" if action_name.blank?

      action = RecordingStudioApi.capability_action(action_name, version: api_version, api: api_key)
      enabled = action && RecordingStudioApi.capability_action_enabled_for?(action, recordable_type, api: api_key)
      return action if enabled

      raise RecordingStudioApi::UnsupportedActionError, catalog.unknown_action_message(action_name, recordable_type)
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
