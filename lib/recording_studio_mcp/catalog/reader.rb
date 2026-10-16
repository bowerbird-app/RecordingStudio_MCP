# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module Reader
      def describe(type_name)
        recordable_type = resolve_type!(type_name)
        registration = registration_for(recordable_type)
        {
          "type" => recordable_type,
          "operations" => Array(registration&.operations).map(&:to_s),
          "writable_fields" => FieldSchema.for(recordable_type, registration),
          "capability_actions" => enabled_capability_actions(recordable_type),
          "parent" => parent_rules(recordable_type)
        }.compact
      end

      def resolve_type!(type_name)
        raise RecordingStudioApi::InvalidActionInputError, "type is required" if type_name.blank?

        name = type_name.to_s
        return name if registered_types.include?(name)

        from_resource = resource_type_name(name)
        return from_resource if from_resource.present? && registered_types.include?(from_resource)

        raise RecordingStudioApi::NotFoundError, unknown_type_message(name)
      end

      def unknown_type_message(name)
        "Unknown type #{name}. #{allowed_types_sentence}"
      end

      def unknown_action_message(action_name, recordable_type)
        allowed = enabled_capability_action_names(recordable_type)
        suffix = allowed.any? ? allowed.join(", ") : "(none)"
        "Unknown action #{action_name}. Allowed actions for #{recordable_type}: #{suffix}"
      end

      def allowed_types_sentence
        suffix = type_names.any? ? type_names.join(", ") : "(none)"
        "Allowed types: #{suffix}"
      end

      def enabled_capability_action_names(recordable_type)
        enabled_action_registrations(recordable_type).map { |action| action.name.to_s }.sort
      end

      def writable_fields(recordable_type)
        Array(registration_for(recordable_type)&.writable_attributes).map(&:to_s)
      end

      private

      def enabled_capability_actions(recordable_type)
        enabled_action_registrations(recordable_type).sort_by { |action| action.name.to_s }.map do |action|
          capability_action_details(action)
        end
      end

      def capability_action_details(action)
        details = { "name" => action.name.to_s }
        contract = action.input_contract&.as_json
        details["params"] = contract.deep_stringify_keys if contract.present?
        details
      end

      def enabled_action_registrations(recordable_type)
        version = RecordingStudioApi.default_api_version(api: api)
        Array(registration_for(recordable_type)&.capability_actions).filter_map do |name|
          RecordingStudioApi.capability_action(name, version: version, api: api)
        end
      end

      def resource_type_name(name)
        RecordingStudioApi.recordable_type_for_resource(name, api: api) ||
          RecordingStudioApi.recordable_type_for_resource(name.pluralize, api: api)
      end

      def parent_rules(recordable_type)
        rules = {}
        assign_root_rule(rules, recordable_type)
        assign_parent_rule(rules, recordable_type)
        rules.presence
      end

      def assign_root_rule(rules, recordable_type)
        return unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:root_allowed?)

        rules["root"] = RecordingStudio.root_allowed?(recordable_type)
      end

      def assign_parent_rule(rules, recordable_type)
        return unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:allowed_parent_types_for)

        parents = Array(RecordingStudio.allowed_parent_types_for(recordable_type))
        rules["allowed_parent_types"] = parents.map(&:to_s).sort
      end
    end
  end
end
