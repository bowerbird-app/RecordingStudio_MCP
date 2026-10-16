# frozen_string_literal: true

module RecordingStudioMcp
  module Tools
    TREE_NAMES = %w[list show create update delete capability_action describe].freeze
    TREE_OPERATION_TOOLS = {
      index: "list",
      show: "show",
      create: "create",
      update: "update",
      destroy: "delete"
    }.freeze

    module_function

    def definitions(access_grant: nil, api: nil)
      ToolSurface.for(access_grant: access_grant, api: api).tool_definitions
    end

    def advertised_tree_names(catalog)
      operations = Array(catalog.visible_operations).map(&:to_sym)
      names = TREE_OPERATION_TOOLS.filter_map do |operation, name|
        name if operations.include?(operation)
      end
      names << "capability_action" if catalog.capability_actions?
      names << "describe"
      names
    end

    def tree_definitions(catalog)
      advertised_tree_names(catalog).map { |name| public_send("#{name}_tool", catalog) }
    end

    def endpoint_tool(endpoint, api: nil)
      tool(endpoint_tool_options(endpoint, api))
    end

    def metric_tool(recordable_metric)
      tool(recordable_metric.definition_options)
    end

    def endpoint_tool_options(endpoint, api)
      schema = FileParams.apply(EndpointSchema.build(endpoint), endpoint)
      options = {
        name: endpoint.name,
        title: endpoint_title(endpoint),
        description: endpoint_description(endpoint),
        read_only: endpoint.http_verb == :get,
        destructive: endpoint.http_verb == :delete,
        idempotent: endpoint.http_verb == :get,
        required: schema.fetch(:required),
        properties: schema.fetch(:properties)
      }
      options[:additional_properties] = schema[:additionalProperties] if schema.key?(:additionalProperties)
      options.merge(api: api, file_params: FileParams.names(endpoint))
    end

    def list_tool(catalog)
      tool(
        name: "list",
        title: "List records",
        description: "List records of one type on this OauthClient's named API. " \
                     "Use describe first if you do not know the type. " \
                     "Send pagination_token from meta.next_pagination_token to get the next page. " \
                     "Returns records and meta.",
        read_only: true,
        idempotent: true,
        required: ["type"],
        properties: {
          type: catalog.type_schema_for(:index),
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
        title: "Show a record",
        description: "Show one record by id. Use list or a create result to get ids. Returns the record.",
        read_only: true,
        idempotent: true,
        required: %w[type id],
        properties: {
          type: catalog.type_schema_for(:show),
          id: { type: "string", description: "Recording id." }
        }
      )
    end

    def create_tool(catalog)
      tool(
        name: "create",
        title: "Create a record",
        description: "Changes data by creating a record. Send writable fields at the root, " \
                     "for example title, not nested under attributes. " \
                     "Child types need parent_id. Call describe for writable fields and parent rules. " \
                     "Returns the created record.",
        read_only: false,
        destructive: false,
        idempotent: true,
        additional_properties: true,
        required: ["type"],
        properties: {
          type: catalog.type_schema_for(:create),
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
        title: "Update a record",
        description: "Changes data by updating a record. Send writable fields at the root, " \
                     "for example title, not nested under attributes. " \
                     "Call describe for the type. Returns the updated record.",
        read_only: false,
        destructive: false,
        idempotent: false,
        additional_properties: true,
        required: %w[type id],
        properties: {
          type: catalog.type_schema_for(:update),
          id: { type: "string", description: "Recording id." }
        }
      )
    end

    def delete_tool(catalog)
      tool(
        name: "delete",
        title: "Delete a record",
        description: "May destructively change data by running the named API destroy operation. " \
                     "Use describe to see which types allow destroy. Returns the delete result.",
        read_only: false,
        destructive: true,
        idempotent: false,
        required: %w[type id],
        properties: {
          type: catalog.destroy_type_schema,
          id: { type: "string", description: "Recording id." }
        }
      )
    end

    def capability_action_tool(catalog)
      tool(
        name: "capability_action",
        title: "Run a capability action",
        description: "May destructively change data by running one named API capability action on a record. " \
                     "Call describe for the type to see which actions are enabled. " \
                     "Returns the action result.",
        read_only: false,
        destructive: true,
        idempotent: false,
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
        title: "Describe a type",
        description: DESCRIBE_DESCRIPTION,
        read_only: true,
        idempotent: true,
        required: ["type"],
        properties: { type: catalog.type_schema }
      )
    end

    DESCRIBE_DESCRIPTION = "Describe one type on this named API. " \
                           "Returns operations, typed writable fields with requirements and allowed values, " \
                           "enabled capability actions with input contracts, and parent rules. " \
                           "Each type's describe output lists its allowed operations."

    def endpoint_title(endpoint)
      endpoint.openapi[:summary].presence || endpoint.name.to_s.tr("_", " ").capitalize
    end

    def endpoint_description(endpoint)
      openapi = endpoint.openapi || {}
      openapi[:description].presence ||
        openapi[:summary].presence ||
        "#{endpoint_title(endpoint)}. #{endpoint.http_verb.to_s.upcase} #{endpoint.path}."
    end

    def tool(options)
      schema = {
        type: "object",
        properties: options.fetch(:properties),
        required: options.fetch(:required)
      }
      schema[:additionalProperties] = options[:additional_properties] if options.key?(:additional_properties)
      payload = {
        name: options.fetch(:name),
        title: options.fetch(:title),
        description: options.fetch(:description),
        inputSchema: schema
      }
      payload[:annotations] = {
        readOnlyHint: options.fetch(:read_only, false),
        destructiveHint: options.fetch(:destructive, false),
        idempotentHint: options.fetch(:idempotent, false),
        openWorldHint: false
      }
      attach_meta(payload, options)
    end

    def attach_meta(payload, options)
      attach_ui_meta(payload, options[:name], options[:api])
      attach_file_params_meta(payload, options[:file_params])
      payload
    end

    def attach_ui_meta(payload, action_name, api)
      return if action_name.blank? || TREE_NAMES.include?(action_name.to_s)

      uri = McpUi.resource_uri_for(action_name: action_name, api: api)
      return if uri.blank?

      payload[:_meta] = (payload[:_meta] || {}).merge(ui: { resourceUri: uri })
    end

    def attach_file_params_meta(payload, names)
      return if names.blank?

      payload[:_meta] = (payload[:_meta] || {}).merge(FileParams::META_KEY => names)
    end
    private_class_method :tool, :endpoint_tool_options, :endpoint_title,
                         :endpoint_description, :attach_meta, :attach_ui_meta, :attach_file_params_meta
  end
end
