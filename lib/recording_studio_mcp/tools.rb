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
    FIELD_META_KEYS = %w[name required type allowed_values description immutable_on_update].freeze

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
        sort: {
          type: "string",
          description: "Sort by a sortable field from describe. created_at is always allowed and is the default. " \
                       "order sets the direction."
        },
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
      built = ToolDocs.decorate(
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
      requirements = create_type_requirements(catalog)
      built[:inputSchema][:allOf] = requirements if requirements.any?
      built
    end

    def create_type_requirements(catalog)
      catalog.type_names_for(:create).filter_map do |type_name|
        fields = schema_fields(catalog, type_name)
        listed = fields.select { |field| field["required"] || nested_field?(field) }
        next if listed.empty?

        type_clause(catalog, type_name, listed, required_fields: fields.select { |field| field["required"] })
      end
    end

    def schema_fields(catalog, type_name)
      registration = RecordingStudioApi.recordable_registration_for(type_name, api: catalog.api)
      FieldSchema.for(type_name, registration)
    end

    def type_clause(catalog, type_name, fields, required_fields: [])
      clause = {
        if: {
          properties: { type: { const: catalog.displayed_type_name(type_name) } },
          required: ["type"]
        },
        then: {
          properties: fields.to_h { |field| [field["name"].to_sym, field_input_property(field)] }
        }
      }
      names = required_fields.map { |field| field["name"] }
      clause[:then][:required] = names if names.any?
      clause
    end

    def field_input_property(field)
      property = { type: field.fetch("type") }
      property[:description] = field["description"] if field["description"].present?
      property[:enum] = field["allowed_values"] if field["allowed_values"]
      (field.keys - FIELD_META_KEYS).each { |key| property[key.to_sym] = field[key] }
      property
    end

    def nested_field?(field)
      (field.keys - FIELD_META_KEYS).any?
    end

    def update_tool(catalog)
      built = ToolDocs.decorate(
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
      requirements = update_type_requirements(catalog)
      built[:inputSchema][:allOf] = requirements if requirements.any?
      built
    end

    def update_type_requirements(catalog)
      catalog.type_names_for(:update).filter_map do |type_name|
        fields = schema_fields(catalog, type_name).select do |field|
          nested_field?(field) && !field["immutable_on_update"]
        end
        next if fields.empty?

        type_clause(catalog, type_name, fields)
      end
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
            idempotency_key: {
              type: "string",
              description: Catalog::Reader::CAPABILITY_IDEMPOTENCY_KEY
            },
            params: { type: "object", description: "Action input as the named API expects it." }
          }
        ),
        output_schema: ToolDocs.action_output_schema
      )
    end

    def registered_tool(built, catalog)
      registration = built.registration
      lookup = built.lookup
      contract = stringify_contract(lookup&.input_contract)
      properties = contract_properties(contract, registration.input)
      required = SchemaFromContract.required_names(contract)
      required = %w[type] if required.empty? && registration.type.present?
      properties = merge_type_property(properties, registration, catalog)
      ToolDocs.decorate(
        tool(
          name: registration.name,
          title: built.title,
          description: built.description,
          read_only: read_only_target?(registration),
          destructive: destructive_target?(registration),
          idempotent: read_only_target?(registration),
          required: required,
          properties: properties.symbolize_keys
        ),
        output_schema: lookup&.output_schema
      )
    end

    def merge_type_property(properties, registration, catalog)
      return properties unless registration.type.present?
      return properties if properties.key?("type") || properties.key?(:type)

      properties.merge(type: catalog.type_schema)
    end

    def stringify_contract(contract)
      return {} if contract.blank?

      contract.to_h.transform_keys(&:to_s)
    end

    def contract_properties(contract, copy)
      contract.to_h.each_with_object({}) do |(name, field), properties|
        key = name.to_s
        properties[key.to_sym] = SchemaFromContract.property(field, copy: copy[key] || {})
      end
    end

    def read_only_target?(registration)
      registration.target.operation? && %i[index show].include?(registration.target.value)
    end

    def destructive_target?(registration)
      registration.target.operation? && registration.target.value == :destroy
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

    DESCRIBE_DESCRIPTION = "Describe one type on this server. " \
                           "Returns the type paragraph, included tools, skills, and relationships."

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
                         :create_type_requirements, :schema_fields, :type_clause,
                         :field_input_property, :nested_field?, :update_type_requirements,
                         :attach_meta, :attach_ui_meta, :stringify_contract, :contract_properties,
                         :read_only_target?, :destructive_target?
  end
end
