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
        "parent_id" => {
          description: "Parent recording id. Only filters for the listed types. " \
                       "root_id on a record is the workspace, not this parent."
        },
        "q" => { description: "Search across writable and sortable fields." },
        "limit" => { description: "Page size." },
        "sort" => {
          description: "Sort by a sortable field. created_at is always allowed and is the default. " \
                       "order sets the direction."
        },
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
      description: "Changes data by creating a record. Send writable fields at the root, for example title, " \
                   "not nested under attributes. Child types need parent_id. Call describe for included tools " \
                   "and relationships.",
      input: {
        "type" => { description: "Type on this server that allows create." },
        "parent_id" => {
          description: "Parent recording id. The type says which record this one goes in."
        },
        "idempotency_key" => { description: "Create idempotency key. Same as the API Idempotency-Key header." }
      },
      output: "the created record"
    }.freeze

    UPDATE = {
      name: "update",
      operation: :update,
      title: "Update a record",
      description: "Changes data by updating a record. Send writable fields at the root, for example title, " \
                   "not nested under attributes. Call describe for the type.",
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
      description: "May destructively change data by running the named API destroy operation. " \
                   "Call describe to see which types allow destroy.",
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
      description: "May destructively change data by running one named API capability action on a record. " \
                   "Call describe for the type to see which actions are enabled. " \
                   "Root fields override params when both set the same key.",
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
  end
end
