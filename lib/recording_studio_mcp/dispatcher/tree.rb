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
      lookup = resource_lookup(recordable_type, operation_name)
      if custom_lookup?(lookup, recordable_type, operation_name)
        call_resource_handler(lookup.handler, recordable_type, operation_name, args)
      else
        call_builtin_resource(recordable_type, operation_name, args, handler: lookup.handler)
      end
    end

    def resource_lookup(recordable_type, operation_name)
      lookup = RecordingStudioApi.lookup(api: api_key, recordable_type: recordable_type, operation: operation_name)
      if lookup.nil?
        raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}"
      end

      lookup
    end

    def custom_lookup?(lookup, recordable_type, operation_name)
      custom = RecordingStudioApi.resource_handler(recordable_type, operation_name, api: api_key)
      lookup.handler && custom && lookup.handler == custom
    end

    def reject_disabled_operation!(recordable_type, operation_name)
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
      return unless registration && !registration.supports_operation?(operation_name)

      shown = catalog.displayed_type_name(recordable_type)
      raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{shown}"
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

    def builtin_member_recording_for(operation_name, recordable_type, id)
      case operation_name
      when :show, :update then load_recording(recordable_type, id)
      when :destroy then load_recording(recordable_type, id, include_trashed: true)
      end
    end
  end
end
