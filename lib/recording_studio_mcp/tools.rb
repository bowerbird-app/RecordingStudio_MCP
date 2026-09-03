# frozen_string_literal: true

module RecordingStudioMcp
  module Tools
    NAMES = %w[list show create update capability_action].freeze

    module_function

    def definitions
      [
        list_tool,
        show_tool,
        create_tool,
        update_tool,
        capability_action_tool
      ]
    end

    def known?(name)
      NAMES.include?(name.to_s)
    end

    def list_tool
      {
        name: "list",
        description: "List records of one type on the named API this OauthClient is bound to.",
        inputSchema: {
          type: "object",
          properties: {
            type: {
              type: "string",
              description: "Recordable type or API resource name, for example Workspace or workspaces."
            },
            q: { type: "string", description: "Search query across writable and sortable fields." },
            limit: { type: "integer", description: "Page size." },
            sort: { type: "string" },
            order: { type: "string" },
            filter: { type: "object", description: "Attribute filters allowed by the named API." }
          },
          required: ["type"]
        }
      }
    end

    def show_tool
      {
        name: "show",
        description: "Show one record by id on the named API this OauthClient is bound to.",
        inputSchema: {
          type: "object",
          properties: {
            type: { type: "string" },
            id: { type: "string", description: "Recording id." }
          },
          required: %w[type id]
        }
      }
    end

    def create_tool
      {
        name: "create",
        description: "Create a record on the named API this OauthClient is bound to.",
        inputSchema: {
          type: "object",
          properties: {
            type: { type: "string" },
            parent_id: { type: "string", description: "Parent recording id." },
            attributes: { type: "object", description: "Writable fields for the type." }
          },
          required: ["type"]
        }
      }
    end

    def update_tool
      {
        name: "update",
        description: "Update a record on the named API this OauthClient is bound to.",
        inputSchema: {
          type: "object",
          properties: {
            type: { type: "string" },
            id: { type: "string" },
            attributes: { type: "object", description: "Writable fields for the type." }
          },
          required: %w[type id]
        }
      }
    end

    def capability_action_tool
      {
        name: "capability_action",
        description: "Run one named API capability action on a record, for example move.",
        inputSchema: {
          type: "object",
          properties: {
            type: { type: "string" },
            id: { type: "string" },
            action: { type: "string", description: "Registered capability action name." },
            params: { type: "object", description: "Action input as the named API expects it." }
          },
          required: %w[type id action]
        }
      }
    end
  end
end
