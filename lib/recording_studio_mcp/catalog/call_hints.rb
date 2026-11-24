# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module CallHints
      def parent_rules_for(recordable_type)
        parent_rules(recordable_type) || {}
      end

      def workspace_parent_id(recordable_type)
        root = workspace_root
        identifier = root && workspace_identifier(root)
        return if identifier.blank?
        return unless workspace_parent?(recordable_type, root)

        identifier.to_s
      end

      def server_chosen_create_parent?(recordable_type)
        return false if recordable_type.blank?
        return false unless defined?(RecordingStudioApi) && RecordingStudioApi.respond_to?(:server_create_parent?)

        RecordingStudioApi.server_create_parent?(recordable_type.to_s, api: api)
      end

      def caller_supplies_create_parent?
        names = type_names_for(:create)
        return true if names.empty?

        names.any? { |type| !server_chosen_create_parent?(type) }
      end

      def server_chosen_action_parent?(action_name)
        action = capability_action_for(action_name)
        action.respond_to?(:server_parent?) && action.server_parent?
      end

      def action_request_contract(action)
        return if action.nil?

        action.respond_to?(:request_input_contract) ? action.request_input_contract : action.input_contract
      end

      def action_creates?(action_name, recordable_type = nil)
        action = capability_action_for(action_name)
        return false if action.nil?
        return true if action_flagged_creates?(action)

        creating_types(action_name, recordable_type).any? { |type| handler_creates?(type, action) }
      end

      def repeat_safe_names(recordable_type)
        names = generic_repeat_safe(recordable_type)
        names += named_repeat_safe_tools(recordable_type)
        names += creating_action_names(recordable_type)
        names.uniq.sort
      end

      private

      def workspace_root
        return unless access_grant.respond_to?(:root_recording)

        access_grant.root_recording
      end

      def workspace_identifier(root)
        root.respond_to?(:id) ? root.id : nil
      end

      def workspace_parent?(recordable_type, root)
        root_type = root.respond_to?(:recordable_type) ? root.recordable_type.to_s : ""
        return false if root_type.blank?

        names = allowed_parent_names(recordable_type)
        names.include?(root_type) || names.include?(displayed_type_name(root_type))
      end

      def allowed_parent_names(recordable_type)
        return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:allowed_parent_types_for)

        Array(RecordingStudio.allowed_parent_types_for(recordable_type)).map(&:to_s)
      end

      def capability_action_for(action_name)
        RecordingStudioApi.capability_action(action_name.to_s, api: api)
      end

      def action_flagged_creates?(action)
        action.respond_to?(:creates?) && action.creates?
      end

      def creating_types(action_name, recordable_type)
        Array(recordable_type.presence || type_names_for_action(action_name))
      end

      def handler_creates?(recordable_type, action)
        registration = RecordingStudioApi.resource_handler_registration(recordable_type, action.name, api: api)
        registration.respond_to?(:creates?) && registration.creates?
      end

      def generic_repeat_safe(recordable_type)
        return [] unless create_repeat_safe?(recordable_type)

        ["create"]
      end

      def create_repeat_safe?(recordable_type)
        resolved_server&.tool?("create") && operations_for(recordable_type).include?(:create)
      end

      def named_repeat_safe_tools(recordable_type)
        return [] unless resolved_server

        resolved_server.tools.each_value.filter_map do |tool|
          tool.name if named_tool_repeat_safe?(tool, recordable_type)
        end
      end

      def named_tool_repeat_safe?(tool, recordable_type)
        registration = tool.registration
        return false if registration.nil? || Catalogs::GENERIC_NAMES.include?(tool.name)
        return false unless listed_for_type?(registration, recordable_type)

        named_registration_repeat_safe?(registration, recordable_type)
      end

      def named_registration_repeat_safe?(registration, recordable_type)
        return true if registration.target.operation? && registration.target.value == :create
        return false unless registration.target.action?

        action_creates?(registration.target.value, recordable_type)
      end

      def creating_action_names(recordable_type)
        return [] unless capability_actions_advertised?

        enabled_capability_action_names(recordable_type).select { |name| action_creates?(name, recordable_type) }
      end
    end
  end
end
