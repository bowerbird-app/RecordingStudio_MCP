# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    def self.for(access_grant)
      new(api: api_from(access_grant))
    end

    def self.api_from(access_grant)
      access_grant&.api_client&.api_key.presence || "public"
    end

    def initialize(api:)
      @api = RecordingStudioApi.configuration.fetch_api(api).name
    end

    attr_reader :api

    def type_names
      @type_names ||= registered_types.sort.freeze
    end

    def type_schema
      {
        type: "string",
        enum: type_names,
        description: "Type registered on this named API. Call describe for writable fields and actions."
      }
    end

    def describe(type_name)
      recordable_type = resolve_type!(type_name)
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api)
      {
        "type" => recordable_type,
        "operations" => Array(registration&.operations).map(&:to_s),
        "writable_fields" => Array(registration&.writable_attributes).map(&:to_s),
        "capability_actions" => enabled_capability_action_names(recordable_type),
        "parent" => parent_rules(recordable_type)
      }.compact
    end

    def resolve_type!(type_name)
      raise RecordingStudioApi::InvalidActionInputError, "type is required" if type_name.blank?

      name = type_name.to_s
      return name if registered_types.include?(name)

      from_resource = RecordingStudioApi.recordable_type_for_resource(name, api: api) ||
                      RecordingStudioApi.recordable_type_for_resource(name.pluralize, api: api)
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
      if type_names.any?
        "Allowed types: #{type_names.join(', ')}"
      else
        "Allowed types: (none)"
      end
    end

    def enabled_capability_action_names(recordable_type)
      version = RecordingStudioApi.default_api_version(api: api)
      RecordingStudioApi.capability_actions_for(recordable_type, version: version, api: api).map do |action|
        action.name.to_s
      end.sort
    end

    def writable_fields(recordable_type)
      Array(RecordingStudioApi.recordable_registration_for(recordable_type, api: api)&.writable_attributes).map(&:to_s)
    end

    private

    def registered_types
      registry = RecordingStudioApi.configuration.fetch_api(api).recordable_registry
      registry.to_h.keys.map(&:to_s)
    end

    def parent_rules(recordable_type)
      rules = {}
      if defined?(RecordingStudio) && RecordingStudio.respond_to?(:root_allowed?)
        rules["root"] = RecordingStudio.root_allowed?(recordable_type)
      end
      if defined?(RecordingStudio) && RecordingStudio.respond_to?(:allowed_parent_types_for)
        parents = Array(RecordingStudio.allowed_parent_types_for(recordable_type))
        rules["allowed_parent_types"] = parents.map(&:to_s).sort
      end
      rules.presence
    end
  end
end
