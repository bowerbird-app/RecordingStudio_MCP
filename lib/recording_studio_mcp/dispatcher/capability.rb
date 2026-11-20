# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def dispatch_capability_action(args, type_name: nil)
      named_tool = type_name.present?
      recordable_type = named_recordable_type(type_name) || catalog.resolve_type!(args["type"])
      action = enabled_capability_action!(recordable_type, args["action"].to_s)
      lookup = capability_lookup(recordable_type, action)
      if custom_capability?(lookup, action)
        call_capability_handler(lookup.handler, args, action, recordable_type, named_tool: named_tool)
      else
        run_capability_action(recordable_type, args, action, handler: lookup&.handler, named_tool: named_tool)
      end
    end

    def named_recordable_type(type_name)
      return if type_name.blank?

      name = type_name.to_s
      return name if catalog.displayed_type_names.key?(name)

      raise RecordingStudioApi::NotFoundError, catalog.unknown_type_message(name)
    end

    def capability_lookup(recordable_type, action)
      RecordingStudioApi.lookup(api: api_key, recordable_type: recordable_type, action: action.name)
    end

    def custom_capability?(lookup, action)
      return false if lookup.nil?

      lookup.handler && lookup.handler != action.handler
    end

    def call_capability_handler(handler, args, action, recordable_type, named_tool: false)
      guarded = handler_scope { capability_guard(recordable_type, action, args) }
      return scope_miss_result unless guarded

      context = capability_context(guarded.recording, args, action, recordable_type, named_tool: named_tool)
      result = replay_creating_action(action, recordable_type, context) { handler.call(context) }
      render_handler_result(result)
    end

    def run_capability_action(recordable_type, args, action, handler: nil, named_tool: false)
      recording = load_recording(recordable_type, args["id"])
      authorize_capability!(recording, action)
      context = action_context(recording, args, action, named_tool: named_tool)
      result = replay_creating_action(action, recordable_type, context) do
        { json: serialize_capability_result(action, (handler || action.handler).call(context), args), status: :ok }
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
  end
end
