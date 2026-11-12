# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module Reader
      def describe(type_name)
        recordable_type = resolve_type!(type_name)
        registration = registration_for(recordable_type)
        payload = default_describe_payload(recordable_type, registration)
        apply_describe_payload(payload, type: recordable_type, registration: registration)
      end

      def resolve_type!(type_name)
        raise RecordingStudioApi::InvalidActionInputError, "type is required" if type_name.blank?

        resolve_registered_type(type_name.to_s)
      end

      def unknown_type_message(name)
        "Unknown type #{name}. #{allowed_types_sentence}"
      end

      def ambiguous_type_message(name, matches)
        "Type #{name} matches more than one registered type: #{matches.sort.join(', ')}. Use the full type name."
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

      def resolve_registered_type(name)
        return name if registered_types.include?(name)

        from_resource = resource_type_name(name)
        return from_resource if from_resource.present? && registered_types.include?(from_resource)

        resolve_short_label!(name)
      end

      def resolve_short_label!(name)
        matches = types_for_short_label(name)
        return matches.first if matches.one?
        raise RecordingStudioApi::InvalidActionInputError, ambiguous_type_message(name, matches) if matches.many?

        raise RecordingStudioApi::NotFoundError, unknown_type_message(name)
      end

      def enabled_capability_actions(recordable_type)
        enabled_action_registrations(recordable_type).sort_by { |action| action.name.to_s }.map do |action|
          capability_action_details(action)
        end
      end

      def capability_action_details(action)
        details = { "name" => action.name.to_s }
        contract = action.input_contract&.as_json
        details["params"] = contract.deep_stringify_keys if contract.present?
        details.merge(action_openapi_fields(action))
      end

      def action_openapi_fields(action)
        openapi = action.openapi if action.respond_to?(:openapi)
        return {} unless openapi.is_a?(Hash)

        %w[title summary description].each_with_object({}) do |key, fields|
          value = openapi[key.to_sym].presence || openapi[key].presence
          fields[key] = value if value
        end
      end

      def enabled_action_registrations(recordable_type)
        version = RecordingStudioApi.default_api_version(api: api)
        listed = Array(registration_for(recordable_type)&.capability_actions).filter_map do |name|
          RecordingStudioApi.capability_action(name, version: version, api: api)
        end
        auto = Array(RecordingStudioApi.capability_actions_for(recordable_type, version: version, api: api))
        (listed + auto).uniq { |action| action.name.to_s }
      end

      def resource_type_name(name)
        RecordingStudioApi.recordable_type_for_resource(name, api: api) ||
          RecordingStudioApi.recordable_type_for_resource(name.pluralize, api: api)
      end

      def types_for_short_label(name)
        registered_types.select { |type| type.demodulize == name }
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
