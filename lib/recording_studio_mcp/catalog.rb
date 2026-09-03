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

    def tool_definitions
      [
        list_tool,
        show_tool,
        create_tool,
        update_tool,
        capability_action_tool,
        describe_tool
      ]
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
        rules["allowed_parent_types"] = Array(RecordingStudio.allowed_parent_types_for(recordable_type)).map(&:to_s).sort
      end
      rules.presence
    end

    def list_tool
      {
        name: "list",
        description: "List records of one type on this OauthClient's named API. " \
                     "Use describe first if you do not know the type. " \
                     "Send pagination_token from meta.next_pagination_token to get the next page. " \
                     "Returns records and meta.",
        annotations: { readOnlyHint: true },
        inputSchema: {
          type: "object",
          properties: {
            type: type_schema,
            q: { type: "string", description: "Search query across writable and sortable fields." },
            limit: { type: "integer", description: "Page size." },
            sort: { type: "string" },
            order: { type: "string", description: "asc or desc." },
            filter: { type: "object", description: "Attribute filters allowed by the named API." },
            pagination_token: {
              type: "string",
              description: "Pass meta.next_pagination_token from the previous list result to fetch the next page."
            }
          },
          required: ["type"]
        }
      }
    end

    def show_tool
      {
        name: "show",
        description: "Show one record by id. Use list or a create result to get ids. Returns the record.",
        annotations: { readOnlyHint: true },
        inputSchema: {
          type: "object",
          properties: {
            type: type_schema,
            id: { type: "string", description: "Recording id." }
          },
          required: %w[type id]
        }
      }
    end

    def create_tool
      {
        name: "create",
        description: "Create a record. Send writable fields at the root, for example title, not nested under attributes. " \
                     "Child types need parent_id. Call describe for the type to see writable fields and parent rules. " \
                     "Returns the created record.",
        inputSchema: {
          type: "object",
          additionalProperties: true,
          properties: {
            type: type_schema,
            parent_id: { type: "string", description: "Parent recording id. Required for types that are not roots." },
            idempotency_key: {
              type: "string",
              description: "Create idempotency key. Same as the API Idempotency-Key header."
            }
          },
          required: ["type"]
        }
      }
    end

    def update_tool
      {
        name: "update",
        description: "Update a record. Send writable fields at the root, for example title, not nested under attributes. " \
                     "Call describe for the type. Returns the updated record.",
        inputSchema: {
          type: "object",
          additionalProperties: true,
          properties: {
            type: type_schema,
            id: { type: "string", description: "Recording id." }
          },
          required: %w[type id]
        }
      }
    end

    def capability_action_tool
      {
        name: "capability_action",
        description: "Run one named API capability action on a record. " \
                     "Call describe for the type to see which actions are enabled. Returns the action result.",
        inputSchema: {
          type: "object",
          properties: {
            type: type_schema,
            id: { type: "string", description: "Recording id." },
            action: { type: "string", description: "Enabled capability action name for this type." },
            params: { type: "object", description: "Action input as the named API expects it." }
          },
          required: %w[type id action]
        }
      }
    end

    def describe_tool
      {
        name: "describe",
        description: "Describe one type on this named API. " \
                     "Returns operations, writable fields, enabled capability actions, and parent rules. " \
                     "Use this before create or capability_action.",
        annotations: { readOnlyHint: true },
        inputSchema: {
          type: "object",
          properties: {
            type: type_schema
          },
          required: ["type"]
        }
      }
    end
  end
end
