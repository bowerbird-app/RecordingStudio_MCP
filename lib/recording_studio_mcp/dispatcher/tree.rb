# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def dispatch_tree(name, args)
      case name
      when "describe"
        success_result(catalog.describe(args["type"]))
      when Catalogs::READ_SKILL_NAME
        read_skill_result(args)
      when "capability_action"
        dispatch_capability_action(args)
      else
        dispatch_resource(RESOURCE_TOOLS.fetch(name), args)
      end
    end

    def dispatch_resource(operation_name, args)
      require_member_id!(operation_name, args)
      validate_index_arguments!(args) if operation_name == :index
      recordable_type = prepared_type!(operation_name, args)
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

    def require_member_id!(operation_name, args)
      return unless MEMBER_ID_OPERATIONS.include?(operation_name)
      raise RecordingStudioApi::InvalidActionInputError, "id is required" if args["id"].blank?
    end

    def prepared_type!(operation_name, args)
      recordable_type = catalog.resolve_type!(args["type"])
      assign_default_parent!(recordable_type, args) if operation_name == :create
      recordable_type
    end

    def assign_default_parent!(recordable_type, args)
      @parent_hint_type = recordable_type
      return if args["parent_id"].present?
      return unless catalog.respond_to?(:workspace_parent_id)

      parent_id = catalog.workspace_parent_id(recordable_type)
      args["parent_id"] = parent_id if parent_id.present?
    end

    def read_skill_result(args)
      return error_result("name is required") if args["name"].blank?

      found = visible_skill(args["name"])
      return error_result("Skill was not found") if found.nil?

      success_result("name" => found[0], "text" => found[1])
    end

    def visible_skill(raw)
      name = Skills::SkillName.parse(raw.to_s)
      registration = name && exposed_skill(name)
      document = registration && Skills::Document.read(registration)
      [registration.name, document.text] if document
    end

    def exposed_skill(name)
      RecordingStudioMcp.exposed_skills(access_grant: access_grant).find { |skill| skill.name == name }
    end
  end
end
