# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module Reader
      CAPABILITY_IDEMPOTENCY_KEY = "Optional. On an action flagged creates: true, the same key and the same input " \
                                   "return the first result. A different input with that key is refused. " \
                                   "Other actions ignore this key. The Idempotency-Key header counts too."

      def describe(type_name)
        describe_registered(resolve_type!(type_name))
      end

      def describe_registered(recordable_type)
        registration = registration_for(recordable_type)
        payload = default_describe_payload(recordable_type, registration)
        apply_describe_payload(payload, type: recordable_type, registration: registration)
      end

      def documentation_type(recordable_type)
        registration = registration_for(recordable_type)
        describe_registered(recordable_type).merge(documentation_type_fields(recordable_type, registration))
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
        names = action_tool_names(recordable_type)
        suffix = names.any? ? names.join(", ") : "(none)"
        shown = displayed_type_name(recordable_type)
        "Unknown action #{action_name}. Allowed tools for #{shown}: #{suffix}"
      end

      def allowed_types_sentence
        names = displayed_names_for(type_names)
        suffix = names.any? ? names.join(", ") : "(none)"
        "Allowed types: #{suffix}"
      end

      def enabled_capability_action_names(recordable_type)
        enabled_action_registrations(recordable_type).map { |action| action.name.to_s }.sort
      end

      def writable_fields(recordable_type, operation: nil)
        names = Array(registration_for(recordable_type)&.writable_attributes).map(&:to_s)
        return names unless operation&.to_sym == :update

        names - Array(registration_for(recordable_type)&.immutable_fields).map(&:to_s)
      end

      def parent_required?(recordable_type)
        return false unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:root_allowed?)

        !RecordingStudio.root_allowed?(recordable_type)
      end

      private

      def resolve_registered_type(name)
        match = accepted_type(name, types_shown_as(name)) || accepted_type(name, type_name_matches(name))
        return match if match

        raise RecordingStudioApi::NotFoundError, unknown_type_message(name)
      end

      def types_shown_as(name)
        registered_types.select { |type| displayed_type_name(type) == name }
      end

      def accepted_type(name, matches)
        return matches.first if matches.one?
        return if matches.empty?

        raise RecordingStudioApi::InvalidActionInputError, ambiguous_type_message(name, matches)
      end

      def enabled_capability_actions(recordable_type, title: :docs)
        enabled_action_registrations(recordable_type).sort_by { |action| action.name.to_s }.map do |action|
          capability_action_details(action, recordable_type, title: title)
        end
      end

      def capability_action_details(action, recordable_type, title: :docs)
        details = { "name" => action.name.to_s }
        contract = action.input_contract&.as_json
        details["params"] = contract.deep_stringify_keys if contract.present?
        fields = details.merge(Documentation::Openapi::ActionDocs.copy_for(action, recordable_type))
        fields["title"] = action_title_for(action, recordable_type, title, fields["title"])
        fields["idempotency_key"] = CAPABILITY_IDEMPOTENCY_KEY
        fields
      end

      def enabled_action_registrations(recordable_type)
        version = RecordingStudioApi.default_api_version(api: api)
        listed = Array(registration_for(recordable_type)&.capability_actions).filter_map do |name|
          RecordingStudioApi.capability_action(name, version: version, api: api)
        end
        auto = Array(RecordingStudioApi.capability_actions_for(recordable_type, version: version, api: api))
        (listed + auto).uniq { |action| action.name.to_s }
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
        rules["allowed_parent_types"] = parents.map { |parent| displayed_type_name(parent) }.sort
      end
    end
  end
end
