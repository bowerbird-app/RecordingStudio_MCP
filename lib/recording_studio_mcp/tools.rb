# frozen_string_literal: true

module RecordingStudioMcp
  module Tools
    NAMES = %w[list show create update capability_action describe].freeze

    module_function

    def definitions(access_grant: nil, api: nil)
      catalog = Catalog.new(api: api || Catalog.api_from(access_grant))
      NAMES.map { |name| public_send("#{name}_tool", catalog) }
    end

    def known?(name)
      NAMES.include?(name.to_s)
    end

    def list_tool(catalog)
      tool(
        name: "list",
        description: "List records of one type on this OauthClient's named API. " \
                     "Use describe first if you do not know the type. " \
                     "Send pagination_token from meta.next_pagination_token to get the next page. " \
                     "Returns records and meta.",
        read_only: true,
        required: ["type"],
        properties: {
          type: catalog.type_schema,
          q: { type: "string", description: "Search query across writable and sortable fields." },
          limit: { type: "integer", description: "Page size." },
          sort: { type: "string" },
          order: { type: "string", description: "asc or desc." },
          filter: { type: "object", description: "Attribute filters allowed by the named API." },
          pagination_token: {
            type: "string",
            description: "Pass meta.next_pagination_token from the previous list result to fetch the next page."
          }
        }
      )
    end

    def show_tool(catalog)
      tool(
        name: "show",
        description: "Show one record by id. Use list or a create result to get ids. Returns the record.",
        read_only: true,
        required: %w[type id],
        properties: {
          type: catalog.type_schema,
          id: { type: "string", description: "Recording id." }
        }
      )
    end

    def create_tool(catalog)
      tool(
        name: "create",
        description: "Create a record. Send writable fields at the root, " \
                     "for example title, not nested under attributes. " \
                     "Child types need parent_id. Call describe for writable fields and parent rules. " \
                     "Returns the created record.",
        additional_properties: true,
        required: ["type"],
        properties: {
          type: catalog.type_schema,
          parent_id: {
            type: "string",
            description: "Parent recording id. Required for types that are not roots."
          },
          idempotency_key: {
            type: "string",
            description: "Create idempotency key. Same as the API Idempotency-Key header."
          }
        }
      )
    end

    def update_tool(catalog)
      tool(
        name: "update",
        description: "Update a record. Send writable fields at the root, " \
                     "for example title, not nested under attributes. " \
                     "Call describe for the type. Returns the updated record.",
        additional_properties: true,
        required: %w[type id],
        properties: {
          type: catalog.type_schema,
          id: { type: "string", description: "Recording id." }
        }
      )
    end

    def capability_action_tool(catalog)
      tool(
        name: "capability_action",
        description: "Run one named API capability action on a record. " \
                     "Call describe for the type to see which actions are enabled. " \
                     "Returns the action result.",
        required: %w[type id action],
        properties: {
          type: catalog.type_schema,
          id: { type: "string", description: "Recording id." },
          action: { type: "string", description: "Enabled capability action name for this type." },
          params: { type: "object", description: "Action input as the named API expects it." }
        }
      )
    end

    def describe_tool(catalog)
      tool(
        name: "describe",
        description: "Describe one type on this named API. " \
                     "Returns operations, writable fields, enabled capability actions, and parent rules. " \
                     "Use this before create or capability_action.",
        read_only: true,
        required: ["type"],
        properties: { type: catalog.type_schema }
      )
    end

    def tool(options)
      schema = {
        type: "object",
        properties: options.fetch(:properties),
        required: options.fetch(:required)
      }
      schema[:additionalProperties] = true if options[:additional_properties]
      payload = {
        name: options.fetch(:name),
        description: options.fetch(:description),
        inputSchema: schema
      }
      payload[:annotations] = { readOnlyHint: true } if options[:read_only]
      payload
    end
    private_class_method :tool
  end
end
