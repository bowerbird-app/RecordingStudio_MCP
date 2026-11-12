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
      ToolDocs.decorate(
        tool(endpoint_tool_options(endpoint, api)),
        output_schema: ToolDocs.endpoint_output_schema(endpoint)
      )
    end

    def metric_tool(recordable_metric)
      ToolDocs.decorate(
        tool(recordable_metric.definition_options),
        output_schema: ToolDocs.metric_output_schema
      )
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
      options.merge(api: api)
    end

    def list_tool(catalog)
      ToolDocs.decorate(
        tool(
          name: "list",
          title: "List records",
          description: list_description(catalog),
          read_only: true,
          idempotent: true,
          required: ["type"],
          properties: list_properties(catalog)
        ),
        output_schema: ToolDocs.list_output_schema(catalog)
      )
    end

    def list_description(catalog)
      extra = if catalog.list_parent_id?
                "Pass parent_id to list children of that parent. It only filters for the listed types. "
              else
                ""
              end
      "List records of one type on this OauthClient's named API. #{extra}" \
        "Use describe first if you do not know the type. " \
        "Send pagination_token from meta.next_pagination_token to get the next page. " \
        "Returns records and meta."
    end

    def list_properties(catalog)
      properties = {
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
      return properties unless catalog.list_parent_id?

      {
        type: properties[:type],
        parent_id: {
          type: "string",
          description: "Parent recording id. Only filters for the listed types. " \
                       "root_id on a record is the workspace, not this parent."
        }
      }.merge(properties.except(:type))
    end

    def show_tool(catalog)
      ToolDocs.decorate(
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
        ),
        output_schema: ToolDocs.record_output_schema(catalog)
      )
    end

    def create_tool(catalog)
      ToolDocs.decorate(
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
        ),
        output_schema: ToolDocs.record_output_schema(catalog)
      )
    end

    def update_tool(catalog)
      ToolDocs.decorate(
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
        ),
        output_schema: ToolDocs.record_output_schema(catalog)
      )
    end

    def delete_tool(catalog)
      ToolDocs.decorate(
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
        ),
        output_schema: ToolDocs.delete_output_schema
      )
    end

    def capability_action_tool(catalog)
      ToolDocs.decorate(
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
        ),
        output_schema: ToolDocs.action_output_schema
      )
    end

    def describe_tool(catalog)
      ToolDocs.decorate(
        tool(
          name: "describe",
          title: "Describe a type",
          description: DESCRIBE_DESCRIPTION,
          read_only: true,
          idempotent: true,
          required: ["type"],
          properties: { type: catalog.type_schema }
        ),
        output_schema: ToolDocs.describe_output_schema
      )
    end

    DESCRIBE_DESCRIPTION = "Describe one type on this named API. " \
                           "Returns operations, typed writable fields with requirements and allowed values, " \
                           "output keys, extra fields, relationships and allowed children, " \
                           "enabled capability actions with input contracts, and parent rules. " \
                           "Each type's describe output lists its allowed operations."

    def endpoint_title(endpoint)
      endpoint.openapi[:summary].presence || endpoint.name.to_s.tr("_", " ").capitalize
    end

    def endpoint_description(endpoint)
      openapi = endpoint.openapi || {}
      body = openapi[:description].presence ||
             openapi[:summary].presence ||
             "#{endpoint_title(endpoint)}. #{endpoint.http_verb.to_s.upcase} #{endpoint.path}."
      role = endpoint.required_role if endpoint.respond_to?(:required_role)
      [body, Documentation::Openapi::ActionDocs.access_line(role)].compact.join("\n\n")
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
      payload
    end

    def attach_ui_meta(payload, action_name, api)
      return if action_name.blank? || TREE_NAMES.include?(action_name.to_s)

      uri = McpUi.resource_uri_for(action_name: action_name, api: api)
      return if uri.blank?

      payload[:_meta] = (payload[:_meta] || {}).merge(ui: { resourceUri: uri })
    end

    private_class_method :tool, :endpoint_tool_options, :endpoint_title,
                         :endpoint_description, :list_description, :list_properties,
                         :attach_meta, :attach_ui_meta
  end
end
