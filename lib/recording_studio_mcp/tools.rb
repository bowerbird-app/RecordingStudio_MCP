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

    def endpoint_tool(endpoint, api: nil, copy: {})
      ToolDocs.decorate(
        tool(endpoint_tool_options(endpoint, api, copy: copy)),
        output_schema: ToolDocs.endpoint_output_schema(endpoint)
      )
    end

    def metric_tool(built, metric = built.metric)
      ToolDocs.decorate(
        tool(metric_tool_options(built, metric)),
        output_schema: ToolDocs.metric_output_schema
      )
    end

    def metric_tool_options(built, metric)
      metric.definition_options.merge(title: built.title, description: built.description)
    end

    def endpoint_tool_options(endpoint, api, copy: {})
      schema = FileParams.apply(EndpointSchema.build(endpoint, copy: copy), endpoint)
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
        "Call describe if you do not know the type. " \
        "Send pagination_token from meta.next_pagination_token to get the next page. " \
        "Returns records and meta."
    end

    def list_properties(catalog)
      properties = {
        type: catalog.type_schema_for(:index),
        q: protocol_field(:string, "Search query across writable and sortable fields.", allow_blank: true),
        limit: protocol_field(:integer, "Page size."),
        sort: protocol_field(
          :string,
          "Sort by a sortable field. created_at is always allowed and is the default. " \
          "order sets the direction.",
          allow_blank: true
        ),
        order: protocol_field(:string, "asc or desc.", allow_blank: true),
        filter: protocol_field(:object, "Attribute filters allowed by the named API."),
        pagination_token: protocol_field(
          :string,
          "Pass meta.next_pagination_token from the previous list result to fetch the next page.",
          allow_blank: true
        )
      }
      return properties unless catalog.list_parent_id?

      {
        type: properties[:type],
        parent_id: protocol_field(
          :string,
          "Parent recording id. Only filters for the listed types. " \
          "root_id on a record is the workspace, not this parent.",
          allow_blank: true
        )
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
            id: protocol_field(:string, "Recording id.")
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
                       "Child types need parent_id. Call describe for included tools and relationships. " \
                       "Returns the created record.",
          read_only: false,
          destructive: false,
          idempotent: true,
          additional_properties: true,
          required: ["type"],
          properties: {
            type: catalog.type_schema_for(:create),
            parent_id: protocol_field(
              :string,
              "Parent recording id. Required for types that are not roots.",
              required: false,
              allow_blank: true
            ),
            idempotency_key: protocol_field(
              :string,
              "Create idempotency key. Same as the API Idempotency-Key header.",
              allow_blank: true
            )
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
        lookup_clause(catalog, type_name, :create)
      end
    end

    def lookup_clause(catalog, type_name, operation)
      lookup = RecordingStudioApi.lookup(api: catalog.api, recordable_type: type_name, operation: operation)
      contract = SchemaFromContract.stringify(lookup&.input_contract)
      return if contract.blank?

      properties, required = lookup_clause_fields(catalog, lookup, type_name, operation, contract)
      clause = {
        if: {
          properties: { type: { const: catalog.displayed_type_name(type_name) } },
          required: ["type"]
        },
        then: { properties: properties }
      }
      clause[:then][:required] = required if required.any?
      clause
    end

    def lookup_clause_fields(catalog, lookup, type_name, operation, contract)
      properties = SchemaFromContract.properties_for(
        lookup,
        recordable_type: type_name,
        operation: operation,
        api: catalog.api
      )
      required = SchemaFromContract.required_names(contract)
      return [properties, required] unless operation == :create && catalog.parent_required?(type_name)

      [properties.merge(parent_id: parent_id_schema), required | ["parent_id"]]
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
            id: protocol_field(:string, "Recording id.")
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
        lookup_clause(catalog, type_name, :update)
      end
    end

    def delete_tool(catalog)
      ToolDocs.decorate(
        tool(
          name: "delete",
          title: "Delete a record",
          description: "May destructively change data by running the named API destroy operation. " \
                       "Call describe to see which types allow destroy. Returns the delete result.",
          read_only: false,
          destructive: true,
          idempotent: false,
          required: %w[type id],
          properties: {
            type: catalog.destroy_type_schema,
            id: protocol_field(:string, "Recording id.")
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
                       "Root fields override params when both set the same key. " \
                       "Returns the action result.",
          read_only: false,
          destructive: true,
          idempotent: false,
          required: %w[type id action],
          properties: {
            type: catalog.type_schema,
            id: protocol_field(:string, "Recording id."),
            action: protocol_field(:string, "Enabled capability action name for this type."),
            idempotency_key: protocol_field(
              :string,
              Catalog::Reader::CAPABILITY_IDEMPOTENCY_KEY,
              allow_blank: true
            ),
            params: protocol_field(:object, "Action input as the named API expects it.")
          }
        ),
        output_schema: ToolDocs.action_output_schema
      )
    end

    def registered_tool(built, catalog)
      ToolDocs.decorate(tool(registered_tool_options(built, catalog)), output_schema: built.lookup&.output_schema)
    end

    def registered_tool_options(built, catalog)
      registration = built.registration
      properties, required = named_schema_fields(built, catalog, registration)
      {
        name: registration.name,
        title: built.title,
        description: built.description,
        read_only: read_only_target?(registration),
        destructive: destructive_target?(registration),
        idempotent: read_only_target?(registration),
        required: required,
        properties: properties,
        api: catalog.api
      }
    end

    def named_schema_fields(built, catalog, registration)
      dropped = forced_keys(registration, built.lookup)
      properties = drop_forced_keys(lookup_properties(built, catalog, registration), dropped)
      required = SchemaFromContract.required_names(built.lookup&.input_contract) - dropped
      properties, required = apply_named_action_id(registration, properties, required)
      apply_named_create_parent_id(catalog, registration, properties, required)
    end

    def lookup_properties(built, catalog, registration)
      SchemaFromContract.properties_for(
        built.lookup,
        recordable_type: registration.type,
        operation: registration.target.value,
        api: catalog.api,
        copy: registration.input
      )
    end

    def forced_keys(registration, lookup = nil)
      keys = []
      keys << "action" if registration.target.action?
      keys << "type" if registration.type.present? && !keep_contract_type?(registration, lookup)
      keys
    end

    def keep_contract_type?(registration, lookup)
      registration.target.action? && SchemaFromContract.stringify(lookup&.input_contract).key?("type")
    end

    def drop_forced_keys(properties, dropped)
      properties.except(*dropped.map(&:to_sym))
    end

    def apply_named_action_id(registration, properties, required)
      return [properties, required] unless registration.target.action?

      merged = { id: protocol_field(:string, "Recording id.") }.merge(properties)
      [merged, (["id"] + required).uniq]
    end

    def apply_named_create_parent_id(catalog, registration, properties, required)
      return [properties, required] unless registration.target.operation? && registration.target.value == :create
      return [properties, required] unless registration.type.present? && catalog.parent_required?(registration.type)

      merged = properties.merge(parent_id: parent_id_schema)
      [merged, (required | ["parent_id"])]
    end

    def parent_id_schema
      protocol_field(:string, "Parent recording id. Required for types that are not roots.")
    end

    def protocol_field(type, description, required: false, allow_blank: nil)
      blank = allow_blank.nil? ? type != :string : allow_blank
      SchemaFromContract.property(
        { type: type, required: required, allow_blank: blank },
        copy: { description: description }
      )
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
                           "Returns the type paragraph, included tools, skills, relationships, " \
                           "allowed parents, writable fields, and available actions."

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
                         :create_type_requirements, :lookup_clause, :update_type_requirements,
                         :attach_meta, :attach_ui_meta, :forced_keys, :keep_contract_type?,
                         :drop_forced_keys, :apply_named_action_id, :apply_named_create_parent_id,
                         :parent_id_schema, :protocol_field, :read_only_target?, :destructive_target?,
                         :registered_tool_options, :lookup_properties, :metric_tool_options
  end
end
