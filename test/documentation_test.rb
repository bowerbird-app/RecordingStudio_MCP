# frozen_string_literal: true

require "test_helper"

class DocumentationTest < Minitest::Test
  Openapi = RecordingStudioMcp::Documentation::Openapi
  include IsolatedApiConfiguration
  include RecordableMetricToolHelpers

  def test_page_lists_registered_types_tools_and_resource_template
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Folder", operations: %i[index show create update])
      register_tree_type("Page", operations: %i[index show create update])

      page = RecordingStudioMcp::Documentation.page(api: :public)

      assert_equal "public", page.api_key
      assert_equal "Public MCP", page.title
      refute_empty page.instructions
      assert_includes page.overview, "## Authentication"
      refute_equal page.overview, page.instructions
      names = page.tools.map { |tool| tool[:name] || tool["name"] }
      assert_includes names, "list"
      assert_includes names, "describe"
      enums = Array(page.type_schema[:enum] || page.type_schema["enum"])
      assert_includes enums, "Folder"
      assert_includes enums, "Page"
      types = page.types.map { |entry| entry["type"] }
      assert_includes types, "Folder"
      assert_includes types, "Page"
      folder = page.types.find { |entry| entry["type"] == "Folder" }
      assert_includes Array(folder["operations"]), "index"
      assert_equal "recording://{id}", page.resource_template[:uriTemplate]
    end
  end

  def test_operations_page_uses_the_mounted_named_api
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :operations
      RecordingStudioApi.register_endpoint(
        :ops_ping,
        api: :operations,
        http_verb: :get,
        path: "ping",
        openapi: { summary: "Ops ping" },
        handler: ->(_context) { { ok: true } }
      )

      page = RecordingStudioMcp::Documentation.page(api: :operations)

      assert_equal "operations", page.api_key
      names = page.tools.map { |tool| tool[:name] || tool["name"] }
      assert_includes names, "ops_ping"
      refute_includes page.types.map { |entry| entry["type"] }, "Folder"
      refute_includes page.instructions, "Call describe before create"
    end
  end

  def test_page_is_nil_safe_when_describe_raises_a_documented_api_error
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Folder")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      boom = lambda do |*|
        raise RecordingStudioApi::NotFoundError, "Unknown type Folder"
      end
      catalog.stub(:describe, boom) do
        RecordingStudioMcp::Catalog.stub(:new, catalog) do
          page = RecordingStudioMcp::Documentation.page(api: :public)
          folder = page.types.find { |entry| entry["type"] == "Folder" }

          assert_equal [], folder["operations"]
          assert_equal [], folder["writable_fields"]
        end
      end
    end
  end

  def test_unknown_api_raises
    with_isolated_api_configuration do
      error = assert_raises(ArgumentError) { RecordingStudioMcp::Documentation.page(api: :missing) }
      assert_includes error.message, "unknown API"
    end
  end

  def test_openapi_document_uses_live_tools_types_and_resource_template
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_ping_capability
      register_tree_type("Folder", operations: %i[index show create update], capability_actions: %i[ping])
      register_tree_type("Page", operations: %i[index show create update])
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        openapi: { summary: "Ping" },
        handler: ->(_context) { { ok: true } }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      mcp = spec.fetch("x-mcp")
      names = mcp.fetch("tools").map { |tool| tool["name"] }
      schemas = spec.dig("components", "schemas")
      folder = schemas.fetch("Folder")
      actions = Array(folder["x-mcp-capability-actions"]).map { |action| action["name"] }

      assert_equal "3.1.0", spec["openapi"]
      assert_equal "Public MCP", spec.dig("info", "title")
      refute_empty spec.dig("info", "description")
      refute_equal spec.dig("info", "description"), mcp["instructions"]
      assert_includes spec.dig("info", "description"), "## Authentication"
      assert_includes mcp["instructions"], "Call describe before create"
      assert_includes names, "list"
      assert_includes names, "describe"
      assert_includes names, "ping"
      assert_includes schemas.keys, "Folder"
      assert_includes schemas.keys, "Page"
      assert_includes Array(folder["x-mcp-operations"]), "index"
      refute folder.key?("x-mcp-writable-fields")
      assert_includes folder.fetch("properties").keys, "title"
      assert_includes actions, "ping"
      assert_equal "recording://{id}", mcp.dig("resources", 0, "uri")
      assert_equal "recording://{id}", mcp.dig("resourceTemplates", 0, "uriTemplate")
      refute Openapi.respond_to?(:servers)
      refute Openapi.respond_to?(:stringify)
    end
  end

  def test_openapi_groups_tools_and_lists_type_actions_and_output_schemas
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Folder", operations: %i[index show create update], capability_actions: %i[ping])
      RecordingStudioApi.register_capability_action(
        :ping,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } },
        input_contract: {
          fields: {
            style: { type: :string, required: false, enum: %w[quiet loud] }
          }
        }
      )
      RecordingStudioApi.register_endpoint(
        :list_agent_chats,
        http_verb: :get,
        path: "agent_chats",
        openapi: {
          summary: "List agent chats",
          tags: ["Agent chats"],
          responses: {
            "200" => {
              description: "ok",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: { chats: { type: "array" } },
                    required: ["chats"]
                  }
                }
              }
            }
          }
        },
        handler: ->(_context) { { chats: [] } }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      mcp = spec.fetch("x-mcp")
      tools = mcp.fetch("tools").index_by { |tool| tool["name"] }
      folder = spec.dig("components", "schemas", "Folder")
      ping = Array(folder["x-mcp-capability-actions"]).find { |action| action["name"] == "ping" }
      description = spec.dig("info", "description")

      listed = RecordingStudioMcp::Tools.definitions.index_by { |tool| tool[:name] }
      refute listed.fetch("list").key?(:tags)
      refute listed.fetch("list_agent_chats").key?(:tags)
      assert listed.fetch("list").key?(:outputSchema)

      assert_equal ["Core"], tools.fetch("list")["tags"]
      assert_equal ["Core"], tools.fetch("describe")["tags"]
      assert_equal ["Agent chats"], tools.fetch("list_agent_chats")["tags"]
      assert tools.fetch("list").key?("outputSchema")
      assert_equal "array", tools.dig("list", "outputSchema", "properties", "records", "type")
      assert_equal "object", tools.dig("show", "outputSchema", "type")
      assert_equal ["chats"], tools.dig("list_agent_chats", "outputSchema", "required")
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      assert_includes tag_names, "Core"
      assert_includes tag_names, "Agent chats"
      refute_includes tag_names, "Types"
      assert_equal tag_names.uniq, tag_names
      refute spec.key?("x-tagGroups")
      assert_equal "Folder", folder["title"]
      assert_includes folder["description"], "A folder record in this workspace."
      assert_includes folder["description"], "Type: `Folder`"
      assert_includes folder["description"], "Allowed operations:"
      assert_includes folder["description"], "index"
      assert_includes folder["description"], "create"
      assert_includes folder["description"], "Writable fields: title."
      assert_includes folder["description"], "**ping**"
      assert_includes folder["description"], "style"
      assert_includes folder["description"], "capability_action"
      assert_includes folder["description"], "`describe` lists them at runtime"
      assert ping.dig("params", "fields", "style")
      assert_equal "Tool: capability_action with type `Folder` and action `ping`", ping["description"]
      refute folder.key?("x-tags")
      assert_includes description, "## Authentication"
      assert_includes description, "## Records and parents"
      assert_includes description, "## Listing and pagination"
      assert_includes description, "## Endpoint tools"
      assert_includes description, "## Skills"
      assert_match(/^## /m, description)
      assert_includes description, "\n- "
      refute_includes description, mcp["instructions"]
    end
  end

  def test_operations_overview_omits_tree_sections
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :operations
      RecordingStudioApi.register_endpoint(
        :ops_ping,
        api: :operations,
        http_verb: :get,
        path: "ping",
        openapi: { summary: "Ops ping" },
        handler: ->(_context) { { ok: true } }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :operations)
      description = spec.dig("info", "description")
      ping = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "ops_ping" }

      assert_includes description, "## Authentication"
      assert_includes description, "## Endpoint tools"
      refute_includes description, "## Records and parents"
      refute_includes description, "## Listing and pagination"
      refute_includes description, "Call describe before create"
      assert_equal ["Endpoints"], ping["tags"]
      refute ping.key?("outputSchema")
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      assert_equal tag_names.uniq, tag_names
      refute spec.key?("x-tagGroups")
    end
  end

  def test_openapi_lists_overlapping_endpoint_and_metric_tags_once
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.configuration.api :public
        register_tree_type("Folder", operations: %i[index show])
        RecordingStudioApi.register_endpoint(
          :users,
          http_verb: :get,
          path: "users",
          openapi: { summary: "Users", tags: ["Users"] },
          handler: ->(_context) { { users: [] } }
        )
        RecordingStudioMetrics.register(
          :users,
          model: Folder,
          blast_radius: :site,
          api_authorize: ->(_context) { true }
        ) do
          count :total, title: "Users", description: "How many users.", expose: { api: [:public] }
        end

        spec = RecordingStudioMcp::Documentation.openapi(api: :public)
        tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
        tag_names = spec.fetch("tags").map { |tag| tag["name"] }

        assert_equal ["Users"], tools.fetch("users")["tags"]
        assert_equal ["Users"], tools.fetch("users-total")["tags"]
        assert_equal 1, tag_names.count("Users")
        assert_equal tag_names.uniq, tag_names
        refute spec.key?("x-tagGroups")
      end
    end
  end

  def test_openapi_places_tagged_types_and_actions_under_the_type_tag
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Credit",
        operations: %i[index show],
        capability_actions: %i[ping],
        openapi: { tag: { group: "Press kits", description: "Credits on a press kit." } }
      )
      register_tree_type("Folder", operations: %i[index show])
      register_ping_capability
      RecordingStudioApi.register_endpoint(
        :press_kit_ping,
        http_verb: :get,
        path: "press_kit_ping",
        openapi: {
          summary: "Press kit ping",
          tag: { group: "Press kits" },
          tags: ["Press Kit"]
        },
        handler: ->(_context) { { ok: true } }
      )

      spec = openapi_with_credit_label!
      credit = spec.dig("components", "schemas", "RecordingStudioPresskits::Credit")
      folder = spec.dig("components", "schemas", "Folder")
      ping = Array(credit["x-mcp-capability-actions"]).find { |action| action["name"] == "ping" }
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      tagged_schemas = spec.dig("components", "schemas").except("TypeName")
      schema_tag_pairs = tagged_schemas.flat_map do |name, schema|
        Array(schema["x-tags"]).map { |tag| [name, tag] }
      end

      assert_equal ["Press Kit"], credit["x-tags"]
      refute folder.key?("x-tags")
      assert_equal "Credit", credit["title"]
      assert_equal "Folder", folder["title"]
      assert_includes credit["description"], "Credits on a press kit."
      assert_includes credit["description"], "Type: `RecordingStudioPresskits::Credit`"
      refute_includes credit["description"], "Registered type"
      assert_includes credit["description"], "**ping**"
      assert_includes credit["description"],
                      "Tool: capability_action with type `RecordingStudioPresskits::Credit` and action `ping`"
      assert_includes credit["description"],
                      "These run through the `capability_action` tool; `describe` lists them at runtime."
      refute_includes credit["description"], "Capability action. Call it through"
      assert_equal(
        "Tool: capability_action with type `RecordingStudioPresskits::Credit` and action `ping`",
        ping["description"]
      )
      assert_includes tag_names, "Press Kit"
      refute_includes tag_names, "Press kits"
      refute_includes tag_names, "Types"
      assert_equal 1, tag_names.count("Press Kit")
      assert_equal tag_names.uniq, tag_names
      refute spec.key?("x-tagGroups")
      assert_equal schema_tag_pairs.uniq, schema_tag_pairs
      refute_includes Array(folder["x-tags"]), "Press Kit"
      refute_includes credit["x-tags"], "Types"
    end
  end

  def test_host_tag_groups_are_emitted_when_set_on_the_page
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Folder", operations: %i[index show])
      page = RecordingStudioMcp::Documentation.page(api: :public)
      grouped = page.with(
        tag_groups: [{ "name" => "Host", "tags" => %w[Core] }]
      )

      spec = Openapi.document(grouped)
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }

      assert_equal [{ "name" => "Host", "tags" => %w[Core] }], spec["x-tagGroups"]
      assert_equal %w[Core], tag_names
    end
  end

  def openapi_with_credit_label!
    type = "RecordingStudioPresskits::Credit"
    store = RecordingStudio::Labels.formatters.fetch(:type_label)
    previous = store[type]
    RecordingStudio::Labels.register_formatter(type, type_label: ->(*) { "Credit" })
    RecordingStudioMcp::Documentation.openapi(api: :public)
  ensure
    if previous
      store[type] = previous
    else
      store.delete(type)
    end
  end
end
