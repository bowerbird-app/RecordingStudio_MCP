# frozen_string_literal: true

require "test_helper"

class ToolsTest < Minitest::Test
  def test_tree_names_are_the_parameterized_set
    assert_equal %w[list show create update delete capability_action describe], RecordingStudioMcp::Tools::TREE_NAMES
  end

  def test_definitions_with_types_include_tree_tools
    with_isolated_api_configuration do
      register_tree_type("Page")
      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[list show create update describe read_skill], names
      list = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "list" }
      refute list.key?(:tags)
      assert_equal "array", list.dig(:outputSchema, :properties, :records, :type)
      describe = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "describe" }
      assert describe.key?(:outputSchema)
      assert_includes describe[:description],
                      "Returns the type paragraph, included tools, skills via read_skill, relationships, " \
                      "allowed parents, writable fields, and available actions."
      refute_includes describe[:description], "Use this before"
      refute_includes describe[:description], "Call describe before"
    end
  end

  def test_mixed_type_operations_union_advertises_create
    with_isolated_api_configuration do
      register_tree_type("SupportPage", operations: %i[index show])
      register_tree_type("Page", operations: %i[index show create])
      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[list show create describe read_skill], names
    end
  end

  def test_full_surface_includes_delete_and_capability_action
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type(
        "Workspace",
        operations: %i[index show create update destroy],
        capability_actions: %i[ping]
      )
      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[list show create update delete capability_action describe read_skill], names
    end
  end

  def test_definitions_with_empty_types_and_endpoints_are_endpoint_tools_only
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_mcp_endpoint_tool(:zeta, http_verb: :get, path: "zeta", handler: ->(_context) { { ok: true } })
        register_mcp_endpoint_tool(
          :alpha,
          http_verb: :post,
          path: "alpha/:name",
          handler: ->(_context) { { ok: true } }
        )
        RecordingStudioMcp.register_server(:public, api: :public) { include_tools :alpha, :zeta }

        tools = RecordingStudioMcp::Tools.definitions
        names = tools.map { |tool| tool[:name] }

        assert_equal %w[describe read_skill alpha zeta], names
        refute_includes names, "list"
      end
    end
  end

  def test_mixed_definitions_put_tree_tools_before_sorted_endpoints
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        register_mcp_endpoint_tool(:zeta, http_verb: :get, path: "zeta", handler: ->(_context) { { ok: true } })
        register_mcp_endpoint_tool(:alpha, http_verb: :get, path: "alpha", handler: ->(_context) { { ok: true } })
        ensure_tree_server(:public, extra_tools: %w[alpha zeta])

        names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

        assert_equal %w[list show create update describe read_skill alpha zeta], names
      end
    end
  end

  def test_list_requires_type
    with_isolated_api_configuration do
      register_tree_type("Page")
      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "list" }
      schema = tool.fetch(:inputSchema)

      assert_equal ["type"], schema.fetch(:required)
      assert schema.fetch(:properties).key?(:pagination_token)
      refute schema.fetch(:properties).key?(:parent_id)
      refute_includes tool.fetch(:description), "parent_id"
    end
  end

  def test_list_sort_describes_sortable_fields_and_the_default
    with_isolated_api_configuration do
      register_tree_type("Page")
      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "list" }
      sort = tool.dig(:inputSchema, :properties, :sort)

      assert_equal "string", sort.fetch(:type)
      assert_includes sort.fetch(:description), "sortable field"
      assert_includes sort.fetch(:description), "created_at"
      assert_includes sort.fetch(:description), "default"
      assert_includes sort.fetch(:description), "order sets the direction"
    end
  end

  def test_list_advertises_parent_id_when_a_type_filters_by_it
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        RecordingStudioMcp.configuration.list_parent_id_types = %w[Page]
        tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "list" }
        schema = tool.fetch(:inputSchema)
        parent_id = schema.fetch(:properties).fetch(:parent_id)

        assert_equal "string", parent_id.fetch(:type)
        assert_includes parent_id.fetch(:description), "Parent recording id"
        assert_includes parent_id.fetch(:description), "listed types"
        assert_includes parent_id.fetch(:description), "root_id"
        assert_includes tool.fetch(:description), "parent_id"
        assert_includes tool.fetch(:description), "listed types"
      end
    end
  end

  def test_tools_have_display_titles
    expected = {
      "list" => "List records",
      "show" => "Show a record",
      "create" => "Create a record",
      "update" => "Update a record",
      "capability_action" => "Run a capability action",
      "describe" => "Describe a type"
    }

    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type("Page", capability_actions: %i[ping])
      expected.each do |name, title|
        tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
        assert_equal title, tool[:title], name
      end
    end
  end

  def test_read_tools_are_marked_read_only
    with_isolated_api_configuration do
      register_tree_type("Page")
      %w[list show describe read_skill].each do |name|
        tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
        assert_equal true, tool.dig(:annotations, :readOnlyHint), name
        assert_equal false, tool.dig(:annotations, :destructiveHint), name
        assert_equal true, tool.dig(:annotations, :idempotentHint), name
        assert_equal false, tool.dig(:annotations, :openWorldHint), name
      end
    end
  end

  def test_write_tools_are_marked_as_changing_data
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type("Page", capability_actions: %i[ping])
      create = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "create" }
      update = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "update" }
      action = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "capability_action" }

      [create, update].each do |tool|
        assert_equal false, tool.dig(:annotations, :readOnlyHint), tool[:name]
        assert_equal false, tool.dig(:annotations, :destructiveHint), tool[:name]
        assert_equal false, tool.dig(:annotations, :openWorldHint), tool[:name]
        assert_includes tool[:description], "Changes data"
        assert_includes tool[:description], "Send writable fields at the root"
      end

      assert_equal true, create.dig(:annotations, :idempotentHint)
      assert_equal false, update.dig(:annotations, :idempotentHint)

      assert_equal false, action.dig(:annotations, :readOnlyHint)
      assert_equal true, action.dig(:annotations, :destructiveHint)
      assert_equal false, action.dig(:annotations, :idempotentHint)
      assert_equal false, action.dig(:annotations, :openWorldHint)
      assert_includes action[:description], "destructively change data"
      assert_includes action[:description], "Call describe for the type"
      assert_equal(
        "Optional. On an action flagged creates: true, the same key and the same input " \
        "return the first result. A different input with that key is refused. " \
        "Other actions ignore this key. The Idempotency-Key header counts too.",
        action.dig(:inputSchema, :properties, :idempotency_key, :description)
      )
      refute_includes action.dig(:inputSchema, :required), "idempotency_key"
    end
  end

  def test_read_only_types_advertise_list_show_describe
    with_isolated_api_configuration do
      register_tree_type("SupportPage", operations: %i[index show])
      tools = RecordingStudioMcp::Tools.definitions
      names = tools.map { |tool| tool[:name] }

      assert_equal %w[list show describe read_skill], names
      describe = tools.find { |tool| tool[:name] == "describe" }
      assert_includes describe[:description],
                      "Returns the type paragraph, included tools, skills via read_skill, relationships, " \
                      "allowed parents, writable fields, and available actions."
      refute_includes describe[:description], "Use this before"
      refute_includes describe[:description], "before create"
    end
  end

  def test_delete_is_listed_only_when_a_type_supports_destroy
    with_isolated_api_configuration do
      register_tree_type("Page")
      refute_includes RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }, "delete"

      register_tree_type("SupportPage", operations: %i[index show create update destroy])
      tools = RecordingStudioMcp::Tools.definitions
      delete = tools.find { |tool| tool[:name] == "delete" }

      assert delete
      assert_equal "Delete a record", delete[:title]
      assert_equal false, delete.dig(:annotations, :readOnlyHint)
      assert_equal true, delete.dig(:annotations, :destructiveHint)
      assert_equal false, delete.dig(:annotations, :idempotentHint)
      assert_includes delete[:description], "destructively change data"
      assert_equal ["SupportPage"], delete.dig(:inputSchema, :properties, :type, :enum)
    end
  end

  def test_create_schema_lists_required_fields_for_each_type
    with_isolated_api_configuration do
      register_tree_type(
        "Page",
        openapi: {
          details_schema: {
            properties: {
              title: { type: "string", description: "Page title." }
            },
            required: ["title"]
          }
        }
      )
      RecordingStudioApi.register_recordable_type_api(
        "Article",
        serializer: ->(*) { { body: "Body" } },
        output_keys: %i[body],
        writable_attributes: %i[body],
        operations: %i[index show create],
        openapi: {
          details_schema: {
            properties: {
              body: { type: "string", description: "Article body.", enum: %w[short long] }
            },
            required: ["body"]
          }
        }
      )
      RecordingStudioMcp.register_type(type: "Article", description: "Article records.")
      %w[Page Article].each do |type|
        RecordingStudioApi.register_resource_handler(type, :create, handler: ->(_) { { json: {} } })
      end
      ensure_tree_server(:public)

      RecordingStudio.stub(:root_allowed?, ->(type) { type.to_s != "Page" }) do
        RecordingStudio.stub(:allowed_parent_types_for, lambda { |type|
          type.to_s == "Page" ? %w[Workspace Folder] : []
        }) do
          tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "create" }
          schema = tool.fetch(:inputSchema)
          clauses = schema.fetch(:allOf).index_by { |clause| clause.dig(:if, :properties, :type, :const) }

          assert_equal "create", tool[:name]
          assert_equal ["type"], schema[:required]
          assert_equal true, schema[:additionalProperties]
          assert_equal %w[Article Page], schema.dig(:properties, :type, :enum)
          assert schema[:properties].key?(:parent_id)
          assert schema[:properties].key?(:idempotency_key)
          refute schema[:properties].key?(:title)
          page_title = clauses.fetch("Page").dig(:then, :properties, :title)
          article_body = clauses.fetch("Article").dig(:then, :properties, :body)
          assert_equal %w[title parent_id], clauses.fetch("Page").dig(:then, :required)
          assert_equal "string", page_title[:type]
          assert_equal "Page title.", page_title[:description]
          assert_equal 1, page_title[:minLength]
          assert_equal ["body"], clauses.fetch("Article").dig(:then, :required)
          assert_equal "string", article_body[:type]
          assert_equal %w[short long], article_body[:enum]
        end
      end
    end
  end

  def test_create_and_update_keep_nested_field_schema
    with_isolated_api_configuration do
      register_menu_section
      RecordingStudioMcp.register_type(type: "MenuSection", description: "Menu section records.")
      %i[create update].each do |operation|
        RecordingStudioApi.register_resource_handler("MenuSection", operation, handler: ->(_) { { json: {} } })
      end
      ensure_tree_server(:public)
      create_clause = type_clause("create", "MenuSection")
      update_clause = type_clause("update", "MenuSection")
      items = create_clause.dig(:then, :properties, :items)

      assert_equal %w[title parent_id], create_clause.dig(:then, :required)
      assert_nil update_clause.dig(:then, :required)
      assert_equal "object", items[:type]
      assert_equal "Labels for kit sections.", items[:description]
      assert_equal "object", items.dig(:additionalProperties, "type")
      assert_equal "string", items.dig(:additionalProperties, "properties", "label", "type")
      assert_equal "boolean", items.dig(:additionalProperties, "properties", "hidden", "type")
      assert_equal [], items.dig(:additionalProperties, "required")
      assert_equal [{ "hero" => { "hidden" => false } }], items[:examples]
      assert_equal items, update_clause.dig(:then, :properties, :items)
    end
  end

  def test_named_crud_tools_advertise_the_same_protocol_fields_as_generic_tools
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type(
        "Page",
        operations: %i[index show create update destroy],
        capability_actions: %i[ping]
      )
      RecordingStudioApi.register_default_resource_actions!(api: :public)
      RecordingStudioMcp.configuration.list_parent_id_types = %w[Page]
      names = register_named_page_tools
      tools = RecordingStudioMcp::Tools.definitions.index_by { |tool| tool[:name] }
      generic_list = tools.fetch("list").fetch(:inputSchema)
      generic_id = tools.fetch("show").dig(:inputSchema, :properties, :id)

      index = tools.fetch(names.fetch(:index)).fetch(:inputSchema)
      refute index.fetch(:properties).key?(:type)
      %i[q limit sort order filter pagination_token parent_id].each do |key|
        assert_equal generic_list.dig(:properties, key), index.dig(:properties, key), key
      end
      refute_includes index.fetch(:required), "q"
      refute_includes index.fetch(:required), "parent_id"

      show = tools.fetch(names.fetch(:show)).fetch(:inputSchema)
      assert_equal ["id"], show.fetch(:required)
      assert_equal generic_id, show.dig(:properties, :id)
      refute show.fetch(:properties).key?(:type)

      update = tools.fetch(names.fetch(:update)).fetch(:inputSchema)
      assert_includes update.fetch(:required), "id"
      assert_equal generic_id, update.dig(:properties, :id)
      assert_equal 1, update.fetch(:required).count("id")
      refute update.fetch(:properties).key?(:type)

      destroy = tools.fetch(names.fetch(:destroy)).fetch(:inputSchema)
      assert_equal ["id"], destroy.fetch(:required)
      assert_equal generic_id, destroy.dig(:properties, :id)
      refute destroy.fetch(:properties).key?(:type)

      action = tools.fetch(names.fetch(:action)).fetch(:inputSchema)
      assert_includes action.fetch(:required), "id"
      assert_equal generic_id, action.dig(:properties, :id)
    end
  end

  def test_named_action_keeps_contract_id_over_the_protocol_default
    with_isolated_api_configuration do
      RecordingStudioApi.register_capability_action(
        :inspect,
        capability: :accessible,
        input_contract: {
          fields: {
            id: { type: :string, required: true, enum: %w[kept] }
          }
        },
        handler: ->(_) { { json: { ok: true } } }
      )
      register_tree_type("Page", operations: %i[show], capability_actions: %i[inspect])
      name = RecordingStudioMcp.tool_name("Page", :inspect)
      RecordingStudioMcp.register_tool(
        name: name,
        type: "Page",
        action: :inspect,
        title: "Inspect page",
        description: "Inspect a page.",
        input: {},
        output: "the result"
      )
      ensure_tree_server(:public, extra_tools: [name])
      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == name }.fetch(:inputSchema)

      assert_equal %w[kept], schema.dig(:properties, :id, :enum)
      assert_equal ["id"], schema.fetch(:required)
    end
  end

  def test_typed_create_schema_matches_generic_create_for_the_same_type
    with_isolated_api_configuration do
      register_tree_type(
        "Page",
        openapi: {
          details_schema: {
            properties: {
              title: { type: "string", minLength: 1 }
            },
            required: ["title"]
          }
        }
      )
      RecordingStudioApi.register_resource_handler("Page", :create, handler: ->(_) { { json: {} } })
      create_page = RecordingStudioMcp.tool_name("Page", :create)
      RecordingStudioMcp.register_tool(
        name: create_page,
        type: "Page",
        operation: :create,
        title: "Create page",
        description: "Create a page.",
        input: {},
        output: "the page"
      )
      ensure_tree_server(:public, extra_tools: [create_page])

      generic = type_clause("create", "Page").fetch(:then)
      typed = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == create_page }.fetch(:inputSchema)

      assert_equal generic.fetch(:properties), typed.fetch(:properties).except(:idempotency_key)
      assert typed.dig(:properties, :idempotency_key)
      refute_includes typed.fetch(:required), "idempotency_key"
      assert_equal generic.fetch(:required), typed.fetch(:required)
    end
  end

  def test_create_has_no_attributes_envelope
    with_isolated_api_configuration do
      register_tree_type("Page")
      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "create" }.fetch(:inputSchema)

      refute schema.fetch(:properties).key?(:attributes)
      assert_equal true, schema[:additionalProperties]
    end
  end

  def test_endpoint_tool_uses_openapi_and_verb_annotations
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :flatpack_component,
      http_verb: :get,
      path: "flatpack/components/:name",
      handler: ->(_context) { {} },
      openapi: { summary: "Show a component", description: "Return one Flatpack component." }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal "flatpack_component", tool[:name]
    assert_equal "Show a component", tool[:title]
    assert_equal "Return one Flatpack component.", tool[:description]
    refute_includes tool[:description], "GET "
    assert_equal true, tool.dig(:annotations, :readOnlyHint)
    assert_equal true, tool.dig(:annotations, :idempotentHint)
    assert_equal false, tool.dig(:annotations, :destructiveHint)
    assert_equal ["name"], tool.dig(:inputSchema, :required)
    refute tool.key?(:tags)
    refute tool.key?(:outputSchema)
  end

  def test_endpoint_output_schema_passes_through_openapi_responses
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :list_agent_chats,
      http_verb: :get,
      path: "agent_chats",
      handler: ->(_context) { { chats: [] } },
      openapi: {
        summary: "List agent chats",
        tags: ["Agent chats"],
        responses: {
          "200" => {
            content: {
              "application/json" => {
                schema: { type: "object", properties: { chats: { type: "array" } } }
              }
            }
          }
        }
      }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    refute tool.key?(:tags)
    assert_equal "array", tool.dig(:outputSchema, :properties, :chats, :type)
  end

  def test_endpoint_contract_closes_additional_properties
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :shout,
      http_verb: :post,
      path: "shout",
      handler: ->(_context) { {} },
      input_contract: {
        fields: {
          message: { type: :string, required: true }
        }
      }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal false, tool.dig(:inputSchema, :additionalProperties)
    assert_equal false, tool.dig(:annotations, :readOnlyHint)
  end

  def test_show_only_omits_list
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show])
      assert_equal %w[show describe read_skill], RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }.to_a
    end
  end

  def test_index_only_omits_show
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index])
      assert_equal %w[list describe read_skill], RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }.to_a
    end
  end

  def test_type_enums_follow_the_operation
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index show])
      register_tree_type("Article", operations: %i[create])
      tools = RecordingStudioMcp::Tools.definitions.index_by { |tool| tool[:name] }

      assert_equal ["Page"], tools.fetch("list").dig(:inputSchema, :properties, :type, :enum)
      assert_equal ["Page"], tools.fetch("show").dig(:inputSchema, :properties, :type, :enum)
      assert_equal ["Article"], tools.fetch("create").dig(:inputSchema, :properties, :type, :enum)
      assert_equal %w[Article Page], tools.fetch("describe").dig(:inputSchema, :properties, :type, :enum)
      refute tools.key?("update")
    end
  end

  def test_view_ping_keeps_destructive_capability_action_hints
    with_isolated_api_configuration do
      register_ping_capability(required_role: :view)
      register_tree_type("Workspace", operations: %i[index show], capability_actions: %i[ping])
      action = RecordingStudioMcp::Tools.definitions(access_grant: role_grant(:view)).find do |tool|
        tool[:name] == "capability_action"
      end

      assert action
      assert_equal false, action.dig(:annotations, :readOnlyHint)
      assert_equal true, action.dig(:annotations, :destructiveHint)
    end
  end

  def test_delete_endpoint_is_marked_destructive
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :remove_widget,
      http_verb: :delete,
      path: "widgets/:id",
      handler: ->(_context) { {} }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal false, tool.dig(:annotations, :readOnlyHint)
    assert_equal true, tool.dig(:annotations, :destructiveHint)
    assert_equal false, tool.dig(:annotations, :idempotentHint)
  end

  def test_endpoint_without_openapi_uses_a_human_description
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :users,
      http_verb: :get,
      path: "users",
      handler: ->(_context) { {} }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal "Users", tool[:title]
    assert_equal "Users. GET users.", tool[:description]
  end

  def test_endpoint_prefers_openapi_description_over_verb_and_path
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :users_create,
      http_verb: :post,
      path: "users",
      handler: ->(_context) { {} },
      openapi: { summary: "Create a user", description: "Requires Accessible :edit on AdminRoot." }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal "Create a user", tool[:title]
    assert_equal "Requires Accessible :edit on AdminRoot.", tool[:description]
  end

  def register_menu_section
    RecordingStudioApi.register_recordable_type_api(
      "MenuSection",
      serializer: ->(*) { { title: "Menu" } },
      output_keys: %i[title],
      writable_attributes: %i[title items],
      operations: %i[index show create update],
      openapi: {
        details_schema: {
          properties: {
            title: { type: "string" },
            items: {
              type: "object",
              description: "Labels for kit sections.",
              additionalProperties: {
                type: "object",
                properties: {
                  label: { type: "string" },
                  hidden: { type: "boolean" }
                },
                required: []
              },
              examples: [{ "hero" => { "hidden" => false } }]
            }
          },
          required: ["title"]
        }
      }
    )
  end

  def test_typeless_named_action_schema_includes_contract_fields_and_id
    with_isolated_api_configuration do
      register_upload_action
      register_tree_type("Page", capability_actions: %i[create_upload])
      RecordingStudioMcp.register_tool(
        name: "create_upload",
        action: :create_upload,
        title: "Create upload",
        description: "Create an upload on the host type passed in args.",
        input: {},
        output: "the upload"
      )
      ensure_tree_server(:public, extra_tools: %w[create_upload])

      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "create_upload" }.fetch(:inputSchema)
      properties = schema.fetch(:properties)

      assert properties.key?(:id)
      assert properties.key?(:filename)
      assert properties.key?(:byte_size)
      refute properties.key?(:action)
      assert properties.key?(:type)
      assert_includes schema.fetch(:required), "type"
      assert_includes schema.fetch(:required), "id"
      assert_includes schema.fetch(:required), "filename"
    end
  end

  def test_typeless_named_action_schema_requires_type
    with_isolated_api_configuration do
      register_upload_action
      register_tree_type("Page", capability_actions: %i[create_upload])
      register_tree_type("Folder", operations: %i[index show])
      RecordingStudioMcp.register_tool(
        name: "create_upload",
        action: :create_upload,
        title: "Create upload",
        description: "Create an upload on the host type passed in args.",
        input: {},
        output: "the upload"
      )
      ensure_tree_server(:public, extra_tools: %w[create_upload])

      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "create_upload" }.fetch(:inputSchema)

      assert_includes schema.fetch(:required), "type"
      assert_equal %w[Page], schema.dig(:properties, :type, :enum)
    end
  end

  def test_typeless_generic_list_schema_stays_protocol_only
    with_isolated_api_configuration do
      register_tree_type("Page")
      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "list" }.fetch(:inputSchema)

      assert_equal ["type"], schema.fetch(:required)
      assert schema.fetch(:properties).key?(:type)
      assert schema.fetch(:properties).key?(:pagination_token)
      refute schema.fetch(:properties).key?(:filename)
    end
  end

  def test_typed_named_action_schema_still_drops_forced_type_and_action
    with_isolated_api_configuration do
      register_upload_action
      register_tree_type("Page", capability_actions: %i[create_upload])
      name = RecordingStudioMcp.tool_name("Page", :create_upload)
      RecordingStudioMcp.register_tool(
        name: name,
        type: "Page",
        action: :create_upload,
        title: "Create page upload",
        description: "Create an upload on a page.",
        input: {},
        output: "the upload"
      )
      ensure_tree_server(:public, extra_tools: [name])

      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == name }.fetch(:inputSchema)
      properties = schema.fetch(:properties)

      assert properties.key?(:id)
      assert properties.key?(:filename)
      refute properties.key?(:type)
      refute properties.key?(:action)
    end
  end

  def register_named_page_tools
    names = {
      index: RecordingStudioMcp.tool_name("Page", :index),
      show: RecordingStudioMcp.tool_name("Page", :show),
      update: RecordingStudioMcp.tool_name("Page", :update),
      destroy: RecordingStudioMcp.tool_name("Page", :destroy),
      action: RecordingStudioMcp.tool_name("Page", :ping)
    }
    {
      names[:index] => [:index, "List pages", "List pages."],
      names[:show] => [:show, "Show page", "Show a page."],
      names[:update] => [:update, "Update page", "Update a page."],
      names[:destroy] => [:destroy, "Delete page", "Delete a page."]
    }.each do |name, (operation, title, description)|
      RecordingStudioMcp.register_tool(
        name: name,
        type: "Page",
        operation: operation,
        title: title,
        description: description,
        input: {},
        output: "the page"
      )
    end
    RecordingStudioMcp.register_tool(
      name: names[:action],
      type: "Page",
      action: :ping,
      title: "Ping page",
      description: "Ping a page.",
      input: {},
      output: "the result"
    )
    ensure_tree_server(:public, extra_tools: names.values)
    names
  end

  def type_clause(tool_name, type_name)
    tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == tool_name }
    tool.dig(:inputSchema, :allOf).find { |clause| clause.dig(:if, :properties, :type, :const) == type_name }
  end

  def register_upload_action
    RecordingStudioApi.register_capability_action(
      :create_upload,
      capability: :attachable,
      input_contract: {
        fields: {
          filename: { type: :string, required: true },
          byte_size: { type: :integer, required: true }
        }
      },
      handler: ->(_context) { { json: { ok: true } } }
    )
  end
end
