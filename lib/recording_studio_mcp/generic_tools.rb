# frozen_string_literal: true

module RecordingStudioMcp
  module GenericTools
    LIST = {
      name: "list",
      operation: :index,
      title: "List records",
      description: "List records of one type on this server. Call describe if you do not know the type. " \
                   "Send pagination_token from meta.next_pagination_token for the next page.",
      input: {
        "type" => { description: "Type on this server." },
        "parent_id" => { description: "Parent recording id. Only filters for types that list children." },
        "q" => { description: "Search across writable and sortable fields." },
        "limit" => { description: "Page size." },
        "sort" => { description: "Sortable field from describe. created_at is the default." },
        "order" => { description: "asc or desc." },
        "filter" => { description: "Attribute filters allowed by the named API." },
        "pagination_token" => { description: "Pass meta.next_pagination_token from the previous list result." }
      },
      output: "records and meta"
    }.freeze

    SHOW = {
      name: "show",
      operation: :show,
      title: "Show a record",
      description: "Show one record by id. Use list or a create result to get ids.",
      input: {
        "type" => { description: "Type on this server." },
        "id" => { description: "Recording id." }
      },
      output: "the record"
    }.freeze

    CREATE = {
      name: "create",
      operation: :create,
      title: "Create a record",
      description: "Create a record. Send writable fields at the root, for example title, not nested under " \
                   "attributes. Child types need parent_id. Call describe for writable fields and parent rules.",
      input: {
        "type" => { description: "Type on this server that allows create." },
        "parent_id" => { description: "Parent recording id. Required for types that are not roots." },
        "idempotency_key" => { description: "Create idempotency key. Same as the API Idempotency-Key header." }
      },
      output: "the created record"
    }.freeze

    UPDATE = {
      name: "update",
      operation: :update,
      title: "Update a record",
      description: "Update a record. Send writable fields at the root, for example title, not nested under " \
                   "attributes. Call describe for the type.",
      input: {
        "type" => { description: "Type on this server that allows update." },
        "id" => { description: "Recording id." }
      },
      output: "the updated record"
    }.freeze

    DELETE = {
      name: "delete",
      operation: :destroy,
      title: "Delete a record",
      description: "Run the named API destroy operation. Call describe to see which types allow destroy.",
      input: {
        "type" => { description: "Type on this server that allows destroy." },
        "id" => { description: "Recording id." }
      },
      output: "the delete result"
    }.freeze

    CAPABILITY_ACTION = {
      name: "capability_action",
      action: :capability_action,
      title: "Run a capability action",
      description: "Run one named API capability action on a record. Call describe for the type to see which " \
                   "actions are enabled.",
      input: {
        "type" => { description: "Type on this server." },
        "id" => { description: "Recording id." },
        "action" => { description: "Enabled capability action name for this type." },
        "idempotency_key" => {
          description: "Optional. On an action flagged creates: true, the same key and the same input " \
                       "return the first result. A different input with that key is refused. " \
                       "Other actions ignore this key. The Idempotency-Key header counts too."
        },
        "params" => { description: "Action input as the named API expects it." }
      },
      output: "the action result"
    }.freeze

    DEFINITIONS = [LIST, SHOW, CREATE, UPDATE, DELETE, CAPABILITY_ACTION].freeze

    module_function

    def install(configuration)
      DEFINITIONS.each do |definition|
        configuration.add_tool(tool_from(definition), override: true)
      end
    end

    def names
      DEFINITIONS.map { |definition| definition.fetch(:name) }
    end

    def tool_from(definition)
      kind = definition.key?(:operation) ? :operation : :action
      value = definition[:operation] || definition[:action]
      Registrations::Tool.new(
        name: definition.fetch(:name).to_s,
        type: nil,
        target: Registrations::ToolTarget.new(kind: kind, value: value.to_sym),
        title: definition.fetch(:title),
        description: definition.fetch(:description),
        input: definition.fetch(:input),
        output: definition.fetch(:output)
      )
    end
    private_class_method :tool_from
  end
end
