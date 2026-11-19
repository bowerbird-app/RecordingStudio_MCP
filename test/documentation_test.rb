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
      assert_equal overview_for(page.instructions), page.overview
      assert_includes page.overview, "## Sign in"
      assert_includes page.overview, "A view-only connection gets the same text minus the Make changes part."
      assert_includes page.overview, "A different input for that key is an error."
      refute_includes page.instructions, "view-only connection"
      refute_includes page.overview, "The key applies to create only."
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
      include_api_endpoints(api: :operations, allow_sensitive: true)

      page = RecordingStudioMcp::Documentation.page(api: :operations)

      assert_equal "operations", page.api_key
      names = page.tools.map { |tool| tool[:name] || tool["name"] }
      assert_includes names, "ops_ping"
      refute_includes page.types.map { |entry| entry["type"] }, "Folder"
      refute_includes page.instructions, "Call describe"
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
      catalog.stub(:documentation_type, boom) do
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
      include_api_endpoints(tree: true)

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      mcp = spec.fetch("x-mcp")
      names = mcp.fetch("tools").map { |tool| tool["name"] }
      schemas = spec.dig("components", "schemas")

      assert_equal "3.1.0", spec["openapi"]
      assert_equal "Public MCP", spec.dig("info", "title")
      refute_empty spec.dig("info", "description")
      assert_equal overview_for(mcp["instructions"]), spec.dig("info", "description")
      assert_includes spec.dig("info", "description"), "## Sign in"
      assert_includes mcp["instructions"], "Call the docs for writable fields, children, and actions"
      assert_includes names, "list"
      assert_includes names, "describe"
      assert_includes names, "ping"
      assert_includes names, "Folder--ping"
      assert_equal ["TypeName"], schemas.keys
      refute_includes schemas.keys, "Folder"
      refute_includes schemas.keys, "Page"
      refute mcp.key?("resources")
      refute mcp.key?("resourceTemplates")
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
      include_api_endpoints(tree: true)

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      mcp = spec.fetch("x-mcp")
      tools = mcp.fetch("tools").index_by { |tool| tool["name"] }
      schemas = spec.dig("components", "schemas")
      description = spec.dig("info", "description")

      listed = RecordingStudioMcp::Tools.definitions.index_by { |tool| tool[:name] }
      refute listed.fetch("list").key?(:tags)
      refute listed.fetch("list_agent_chats").key?(:tags)
      assert listed.fetch("list").key?(:outputSchema)

      assert_equal ["Overview"], tools.fetch("list")["tags"]
      assert_equal ["Overview"], tools.fetch("describe")["tags"]
      assert_equal ["Agent chats"], tools.fetch("list_agent_chats")["tags"]
      assert tools.fetch("list").key?("outputSchema")
      assert_equal "array", tools.dig("list", "outputSchema", "properties", "records", "type")
      assert_equal "object", tools.dig("show", "outputSchema", "type")
      assert_equal ["chats"], tools.dig("list_agent_chats", "outputSchema", "required")
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      assert_equal "Overview", tag_names.first
      refute_includes tag_names, "Core"
      refute_includes tag_names, "Tools"
      assert_includes tag_names, "Agent chats"
      refute_includes tag_names, "Types"
      assert_equal tag_names.uniq, tag_names
      refute spec.key?("x-tagGroups")
      assert_equal ["TypeName"], schemas.keys
      refute_includes schemas.keys, "Folder"
      ping_tool = tools.fetch("Folder--ping")
      assert_equal "Folder - Ping", ping_tool["title"]
      assert ping_tool["x-mcp-docs-only"]
      refute tools.fetch("list").key?("x-mcp-docs-only")
      assert_equal "object", ping_tool.dig("inputSchema", "type")
      assert_equal "string", ping_tool.dig("inputSchema", "properties", "style", "type")
      assert_equal %w[quiet loud], ping_tool.dig("inputSchema", "properties", "style", "enum")
      assert_equal false, ping_tool.dig("inputSchema", "additionalProperties")
      assert_equal "quiet", ping_tool.dig("inputSchema", "example", "style")
      refute ping_tool["inputSchema"].key?("fields")
      refute ping_tool["inputSchema"].key?("reject_unknown")
      assert_includes ping_tool["description"], "Runs on Folder records."
      assert_includes ping_tool["description"], "Type: `Folder`"
      refute_includes ping_tool["description"], "Allowed operations:"
      refute_includes ping_tool["description"], "Writable fields:"
      refute_includes ping_tool["description"], "A folder record in this workspace."
      assert_equal ["Tool: capability_action with type `Folder` and action `ping`."],
                   tool_lines(ping_tool["description"])
      refute_includes ping_tool["description"], "idempotency_key"
      refute_includes ping_tool["description"], "Tool: list"
      refute_includes ping_tool["description"], "style"
      refute_includes ping_tool["description"], "reject_unknown"
      assert_equal ["Folder"], ping_tool["tags"]
      assert_includes description, "## Sign in"
      assert_includes description, "## Walk your records"
      assert_includes description, "## Guides"
      assert_match(/^## /m, description)
      refute_includes description, "If you only see named route tools"
      assert_equal overview_for(mcp["instructions"]), description
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
      include_api_endpoints(api: :operations, allow_sensitive: true)

      spec = RecordingStudioMcp::Documentation.openapi(api: :operations)
      description = spec.dig("info", "description")
      ping = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "ops_ping" }

      assert_includes description, "## Sign in"
      assert_includes description, "## If you only see named route tools"
      refute_includes description, "## Walk your records"
      refute_includes description, "Call describe"
      assert_equal ["Other tools"], ping["tags"]
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
        include_metric_server
        include_api_endpoints(tree: true)

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
      include_api_endpoints(tree: true)

      spec = openapi_with_credit_label!
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      press_kit = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }
      ping_tool = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "Credit--ping" }
      ping_description = ping_tool.fetch("description")
      runs_at = ping_description.index("Runs on Credit records.")
      type_description_at = ping_description.index("Credits on a press kit.")
      type_line_at = ping_description.index("Type: `Credit`")

      refute_includes spec.dig("components", "schemas").keys, "RecordingStudioPresskits::Credit"
      refute_includes spec.dig("components", "schemas").keys, "Folder"
      assert_equal "Credit - Ping", ping_tool["title"]
      assert_equal ["Press Kit"], ping_tool["tags"]
      assert_includes ping_tool["description"],
                      "Runs on Credit records."
      assert_includes ping_tool["description"], "Credits on a press kit."
      assert_operator type_description_at, :>, runs_at
      assert_operator type_line_at, :>, type_description_at
      assert_includes ping_tool["description"], "Type: `Credit`"
      refute_includes ping_tool["description"], "Allowed operations:"
      refute_includes ping_tool["description"], "Writable fields:"
      assert_equal ["Tool: capability_action with type `Credit` and action `ping`."],
                   tool_lines(ping_tool["description"])
      refute_includes ping_tool["description"], "Tool: list"
      assert_includes press_kit["description"], "Credits on a press kit."
      assert_includes press_kit["description"], "Tool: list with type `Credit`"
      assert_includes press_kit["description"], "Tool: show with type `Credit` and id"
      refute_includes press_kit["description"], "Tool: create"
      assert_includes tag_names, "Press Kit"
      refute_includes tag_names, "Press kits"
      refute_includes tag_names, "Types"
      assert_equal 1, tag_names.count("Press Kit")
      assert_equal tag_names.uniq, tag_names
      refute spec.key?("x-tagGroups")
    end
  end

  def test_action_pages_end_with_tool_lines_for_allowed_operations
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        RecordingStudioMcp.configuration.list_parent_id_types = %w[RecordingStudioPresskits::PressKit]
        register_ping_capability
        register_tree_type(
          "RecordingStudioPresskits::PressKit",
          operations: %i[index show create update destroy],
          capability_actions: %i[ping]
        )
        register_tree_type("Note", operations: %i[index show], capability_actions: %i[ping])
        register_tree_type("Message", operations: %i[show])

        spec = press_kit_parent_spec
        tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
        names = tools.keys
        press = tools.fetch("PressKit--ping")["description"]
        note = tools.fetch("Note--ping")["description"]

        press_intro = spec.fetch("tags").find { |tag| tag["name"] == "PressKit" }.fetch("description")
        note_intro = spec.fetch("tags").find { |tag| tag["name"] == "Note" }.fetch("description")
        message_intro = spec.fetch("tags").find { |tag| tag["name"] == "Message" }.fetch("description")

        assert tools.fetch("PressKit--ping")["x-mcp-docs-only"]
        refute_includes names, "PressKit--list"
        refute_includes names, "Note--list"
        refute_includes names, "Message--show"
        assert_equal ["Tool: capability_action with type `PressKit` and action `ping`."], tool_lines(press)
        assert_equal ["Tool: capability_action with type `Note` and action `ping`."], tool_lines(note)
        refute_includes press, "Tool: list"
        refute_includes press, "Tool: delete"
        assert_includes press_intro, "Tool: list with type `PressKit` and parent_id (the press center id)"
        assert_includes press_intro, "Tool: show with type `PressKit` and id"
        create_line = "Tool: create with type `PressKit`, parent_id, writable fields at the top level, " \
                      "and optional idempotency_key"
        assert_includes press_intro, create_line
        assert_includes press_intro, "Tool: update with type `PressKit`, id, and writable fields"
        assert press_intro.end_with?("Tool: delete with type `PressKit` and id")
        refute_includes press_intro, "RecordingStudioPresskits::PressKit"
        refute_includes press_intro, "Tool: capability_action"
        assert_includes note_intro, "Tool: list with type `Note` and parent_id"
        refute_includes note_intro, "(the "
        refute_includes note_intro, "Tool: create"
        refute_includes note_intro, "Tool: update"
        refute_includes note_intro, "Tool: delete"
        assert_equal ["Tool: show with type `Message` and id"], tool_lines(message_intro)
      end
    end
  end

  def test_list_tool_line_omits_parent_id_when_the_surface_does_not_advertise_it
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_ping_capability
        register_tree_type("Page", operations: %i[index show create], capability_actions: %i[ping])

        spec = RecordingStudioMcp::Documentation.openapi(api: :public)
        tools = spec.dig("x-mcp", "tools")
        page = tools.index_by { |tool| tool["name"] }.fetch("Page--ping")["description"]
        intro = spec.fetch("tags").find { |tag| tag["name"] == "Page" }.fetch("description")

        assert_equal ["Tool: capability_action with type `Page` and action `ping`."], tool_lines(page)
        refute_includes page, "Tool: list"
        assert_includes intro, "Tool: list with type `Page`\n"
        refute_includes intro, "Tool: list with type `Page` and parent_id"
        create_line = "Tool: create with type `Page`, parent_id, writable fields at the top level, " \
                      "and optional idempotency_key"
        assert_includes intro, create_line
        refute_includes tools.map { |tool| tool["name"] }, "Page--list"
        refute_includes tools.map { |tool| tool["name"] }, "Page--delete"
        refute_includes intro, "Tool: delete"
      end
    end
  end

  def test_docs_pages_omit_operations_the_named_api_does_not_allow
    with_isolated_api_configuration do
      register_named_capability(:search, summary: "Search support articles")
      register_tree_type("Support", operations: %i[index show], capability_actions: %i[search])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      tools = spec.dig("x-mcp", "tools")
      names = tools.map { |tool| tool["name"] }
      page = tools.find { |tool| tool["name"] == "Support--search" }.fetch("description")
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Support" }.fetch("description")

      assert_equal ["Tool: capability_action with type `Support` and action `search`."], tool_lines(page)
      refute_includes page, "Tool: list"
      assert_includes intro, "Tool: list with type `Support`"
      assert_includes intro, "Tool: show with type `Support` and id"
      refute_includes intro, "Tool: capability_action"
      refute_includes intro, "Tool: create"
      refute_includes intro, "Tool: update"
      refute_includes intro, "Tool: delete"
      %w[Support--list Support--show Support--create Support--update Support--delete].each do |name|
        refute_includes names, name
      end
    end
  end

  def test_action_page_names_only_its_own_tool_line
    with_isolated_api_configuration do
      register_tree_type(
        "Identity",
        operations: %i[index show create update destroy],
        capability_actions: %i[identity_remove_image ping]
      )
      register_ping_capability
      RecordingStudioApi.register_capability_action(
        :identity_remove_image,
        capability: :accessible,
        creates: true,
        handler: ->(_context) { { json: { ok: true } } },
        openapi: { summary: "Remove the image" }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      remove = tools.fetch("Identity--identity_remove_image").fetch("description")
      ping = tools.fetch("Identity--ping").fetch("description")
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Identity" }.fetch("description")

      assert_equal 1, tool_lines(remove).size
      assert_includes remove, "Tool: capability_action with type `Identity` and action `identity_remove_image`."
      assert_includes remove,
                      "Pass idempotency_key to replay an action flagged creates: true when the input matches."
      assert_includes remove, "A different input for that key is an error."
      %w[list show create update delete].each { |name| refute_includes remove, "Tool: #{name}" }
      assert_equal ["Tool: capability_action with type `Identity` and action `ping`."], tool_lines(ping)
      refute_includes ping, "idempotency_key"
      assert_equal 1, intro.scan("Tool: list with type `Identity`").size
      assert_includes intro, "Tool: delete with type `Identity` and id"
      refute_includes intro, "Tool: capability_action"
    end
  end

  def test_action_page_includes_idempotency_when_the_resource_handler_creates
    with_isolated_api_configuration do
      register_tree_type("Folder", operations: %i[index show], capability_actions: %i[add_file peek])
      register_named_capability(:add_file, summary: "Add a file")
      register_named_capability(:peek, summary: "Peek at the folder")
      RecordingStudioApi.register_resource_handler(
        "Folder", :add_file, handler: ->(_context) { { json: { ok: true } } }, creates: true
      )

      tools = RecordingStudioMcp::Documentation.openapi(api: :public).dig("x-mcp", "tools")
      indexed = tools.index_by { |tool| tool["name"] }
      add = indexed.fetch("Folder--add_file").fetch("description")
      peek = indexed.fetch("Folder--peek").fetch("description")

      assert_equal 1, tool_lines(add).size
      assert_includes add, "Tool: capability_action with type `Folder` and action `add_file`."
      assert_includes add, "Pass idempotency_key to replay an action flagged creates: true when the input matches."
      assert_equal ["Tool: capability_action with type `Folder` and action `peek`."], tool_lines(peek)
      refute_includes peek, "idempotency_key"
    end
  end

  def test_type_without_actions_still_gets_an_intro_for_allowed_core_tools
    with_isolated_api_configuration do
      register_tree_type(
        "SupportPage",
        operations: %i[index show],
        openapi: { tags: ["Support"] }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      names = spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Support" }.fetch("description")

      assert_includes spec.fetch("tags").map { |tag| tag["name"] }, "Support"
      assert_equal [
        "Tool: list with type `SupportPage`",
        "Tool: show with type `SupportPage` and id"
      ], tool_lines(intro)
      refute(names.any? { |name| name.start_with?("SupportPage--") })
    end
  end

  def test_sidebar_omits_a_tag_with_no_tools_and_no_core_lines
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "EmptyShelf",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        writable_attributes: %i[title],
        operations: %i[index show],
        auto_capability_actions: false,
        openapi: { tags: ["Support"], description: "Nothing to call." }
      )
      lines = RecordingStudioMcp::Documentation::Openapi::TypeOperationLines
      spec = lines.stub(:lines_for, []) do
        RecordingStudioMcp::Documentation.openapi(api: :public)
      end
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }

      refute_includes tag_names, "Support"
      refute_includes spec.to_json, "Nothing to call."
    end
  end

  def press_kit_parent_spec
    parent_for = lambda do |type|
      type.to_s.end_with?("PressKit") ? ["PressCenter"] : []
    end
    RecordingStudio.stub(:allowed_parent_types_for, parent_for) do
      RecordingStudioMcp::Documentation.openapi(api: :public)
    end
  end

  def test_openapi_describes_a_shared_tag_when_type_descriptions_match
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Credit",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"], description: "Credits on a press kit." }
      )
      register_tree_type(
        "RecordingStudioPresskits::KitSection",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"], description: "Credits on a press kit." }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      press_kit = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }

      assert_includes press_kit["description"], "Credits on a press kit."
      assert_equal 1, press_kit["description"].scan("Credits on a press kit.").size
      assert_includes press_kit["description"], "Tool: list with type `Credit`"
      assert_includes press_kit["description"], "Tool: show with type `Credit` and id"
      assert_includes press_kit["description"], "Tool: list with type `KitSection`"
      assert_includes press_kit["description"], "Tool: show with type `KitSection` and id"
    end
  end

  def test_openapi_leaves_a_shared_tag_undescribed_when_type_descriptions_differ
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Credit",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"], description: "Credits on a press kit." }
      )
      register_tree_type(
        "RecordingStudioPresskits::KitSection",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"], description: "Sections in a press kit." }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      press_kit = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }

      assert_equal "Press Kit", press_kit["name"]
      refute_includes press_kit["description"], "Credits on a press kit."
      refute_includes press_kit["description"], "Sections in a press kit."
      assert_includes press_kit["description"], "Tool: list with type `Credit`"
      assert_includes press_kit["description"], "Tool: list with type `KitSection`"
    end
  end

  def test_openapi_lists_capability_actions_as_tagged_tool_entries
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Credit",
        operations: %i[index show create update destroy],
        openapi: { tags: ["Press Kit"] }
      )
      register_tree_type(
        "RecordingStudioPresskits::KitSection",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"] }
      )
      register_tree_type(
        "RecordingStudioPresskits::CreditLine",
        operations: %i[index show],
        capability_actions: %i[remove_credit],
        openapi: { tags: ["Press Kit"] }
      )
      register_tree_type(
        "RecordingStudioPresskits::CreditsSection",
        operations: %i[index show],
        capability_actions: %i[add_credit reorder_credits],
        openapi: { tags: ["Press Kit"] }
      )
      register_named_capability(
        :add_credit,
        summary: "Add a workspace credit to this section",
        input_contract: {
          reject_unknown: true,
          fields: {
            credit_id: { type: :string, required: true, allow_blank: false }
          }
        }
      )
      register_named_capability(:reorder_credits, summary: "Reorder credits in this section")
      register_named_capability(:remove_credit, summary: "Remove a credit from this section")

      spec = stub_allowed_parents(
        "RecordingStudioPresskits::CreditLine" => ["RecordingStudioPresskits::CreditsSection"],
        "RecordingStudioPresskits::CreditsSection" => ["RecordingStudioPresskits::KitSection"]
      ) do
        openapi_with_labels!(
          "RecordingStudioPresskits::Credit" => "Credit",
          "RecordingStudioPresskits::CreditLine" => "credit line",
          "RecordingStudioPresskits::CreditsSection" => "Credits section"
        )
      end
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      titles = spec.dig("x-mcp", "tools").filter_map do |tool|
        tool["title"] if tool["name"].to_s.include?("--")
      end
      schemas = spec.dig("components", "schemas")
      protocol_names = RecordingStudioMcp::Tools.definitions(api: :public).map { |tool| tool[:name] }

      [
        "Credits section - Add Credit",
        "Credits section - Reorder Credits",
        "credit line - Remove Credit"
      ].each { |title| assert_includes titles, title }
      refute_includes protocol_names, "CreditsSection--add_credit"
      add = tools.fetch("CreditsSection--add_credit")
      reorder = tools.fetch("CreditsSection--reorder_credits")
      remove = tools.fetch("CreditLine--remove_credit")
      assert add["x-mcp-docs-only"]
      assert reorder["x-mcp-docs-only"]
      assert remove["x-mcp-docs-only"]
      assert_equal "string", add.dig("inputSchema", "properties", "credit_id", "type")
      assert_equal 1, add.dig("inputSchema", "properties", "credit_id", "minLength")
      assert_equal ["credit_id"], add.dig("inputSchema", "required")
      assert_equal false, add.dig("inputSchema", "additionalProperties")
      assert_equal "credit_id", add.dig("inputSchema", "example", "credit_id")
      refute add["inputSchema"].key?("fields")
      assert_equal({ "type" => "object" }, reorder["inputSchema"])
      assert_equal({ "type" => "object" }, remove["inputSchema"])
      assert_equal "Credits section - Add Credit", add["title"]
      assert_equal ["Press Kit"], add["tags"]
      assert_equal ["Press Kit"], reorder["tags"]
      assert_equal ["Press Kit"], remove["tags"]
      assert_includes add["description"], "Runs on Credits section records (CreditsSection)."
      assert_includes add["description"], "Type: `CreditsSection`"
      refute_includes add["description"], "Allowed operations:"
      refute_includes add["description"], "Writable fields:"
      assert_includes add["description"], "Add a workspace credit to this section"
      assert_includes add["description"],
                      "Tool: capability_action with type `CreditsSection` " \
                      "and action `add_credit`"
      refute_includes add["description"], "credit_id"
      refute_includes add["description"], "reject_unknown"
      assert_includes reorder["description"], "Reorder credits in this section"
      assert_includes remove["description"], "Runs on credit line records (CreditLine)."
      assert_includes remove["description"], "Type: `CreditLine`"
      refute_includes remove["description"], "Allowed operations:"
      refute_includes remove["description"], "Writable fields:"
      assert_equal ["TypeName"], schemas.keys
      refute_includes schemas.keys, "RecordingStudioPresskits::Credit"
      refute_includes schemas.keys, "RecordingStudioPresskits::CreditLine"
      refute_includes schemas.keys, "RecordingStudioPresskits::CreditsSection"
    end
  end

  def test_capability_action_docs_follow_any_registered_type
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "Gallery",
        operations: %i[index show],
        capability_actions: %i[publish],
        openapi: { tags: ["Galleries"] }
      )
      register_tree_type(
        "GallerySection",
        operations: %i[index show],
        capability_actions: %i[add_slide],
        openapi: { tags: ["Galleries"] }
      )
      register_tree_type(
        "GallerySlide",
        operations: %i[index show update],
        capability_actions: %i[remove_slide],
        openapi: { tags: ["Galleries"] }
      )
      register_named_capability(:publish, summary: "Publish this gallery")
      register_named_capability(:add_slide, summary: "Add a slide to this section")
      register_named_capability(:remove_slide, summary: "Remove this slide")

      spec = stub_allowed_parents(
        "GallerySection" => ["Gallery"],
        "GallerySlide" => ["GallerySection"]
      ) { RecordingStudioMcp::Documentation.openapi(api: :public) }
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      schemas = spec.dig("components", "schemas")
      publish = tools.fetch("Gallery--publish")
      add = tools.fetch("GallerySection--add_slide")
      remove = tools.fetch("GallerySlide--remove_slide")
      protocol_names = RecordingStudioMcp::Tools.definitions(api: :public).map { |tool| tool[:name] }

      assert publish["x-mcp-docs-only"]
      assert_equal({ "type" => "object" }, publish["inputSchema"])
      assert_equal({ "type" => "object" }, add["inputSchema"])
      assert_equal "Gallery - Publish", publish["title"]
      assert_equal ["Galleries"], publish["tags"]
      assert_includes publish["description"], "Runs on Gallery records."
      assert_equal "Gallery section - Add Slide", add["title"]
      assert_equal ["Galleries"], add["tags"]
      assert_includes add["description"], "Runs on Gallery section records (GallerySection)."
      assert_includes add["description"], "Type: `GallerySection`"
      refute_includes add["description"], "Allowed operations:"
      refute_includes add["description"], "Writable fields:"
      assert_includes add["description"], "Add a slide to this section"
      assert_includes add["description"],
                      "Tool: capability_action with type `GallerySection` and action `add_slide`"
      assert_equal "Gallery slide - Remove Slide", remove["title"]
      assert_equal ["Galleries"], remove["tags"]
      assert_includes remove["description"], "Runs on Gallery slide records (GallerySlide)."
      refute_includes protocol_names, "GallerySection--add_slide"
      assert_equal ["TypeName"], schemas.keys
      refute_includes schemas.keys, "Gallery"
      refute_includes schemas.keys, "GallerySection"
      refute_includes schemas.keys, "GallerySlide"
    end
  end

  def test_named_tool_for_a_type_action_is_listed_once
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type("Folder", operations: %i[index show], capability_actions: %i[ping])
      register_tree_type("Page", operations: %i[index show], capability_actions: %i[ping])
      RecordingStudioMcp.register_tool(
        name: "folder_ping",
        type: "Folder",
        action: :ping,
        title: "Ping folder",
        description: "Ping a folder.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: %w[folder_ping])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      names = spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }

      assert_equal 1, names.count("folder_ping")
      refute_includes names, "Folder--ping"
      refute tools.fetch("folder_ping")["x-mcp-docs-only"]
      assert_equal 1, names.count("Page--ping")
      assert tools.fetch("Page--ping")["x-mcp-docs-only"]
    end
  end

  def test_openapi_files_actions_use_the_gem_type_group
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::PressKit",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"] }
      )
      register_tree_type(
        "RecordingStudioPresskits::Files",
        operations: %i[index show],
        capability_actions: %i[add_file]
      )
      register_named_capability(:add_file, summary: "Add a file to this section")

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      add = tools.fetch("Files--add_file")

      assert_equal ["Press Kit"], add["tags"]
      refute_includes spec.dig("components", "schemas").keys, "RecordingStudioPresskits::Files"
    end
  end

  def test_openapi_prefixes_humanized_action_names_when_no_title_is_set
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      %w[PressKit Podcast Quote].each do |name|
        register_tree_type(
          "RecordingStudioPresskits::#{name}",
          operations: %i[index show],
          capability_actions: %i[create_upload],
          openapi: { tags: ["Press Kit"] }
        )
      end
      register_named_capability(:create_upload, summary: "Create an upload")

      spec = openapi_with_labels!(
        "RecordingStudioPresskits::PressKit" => "Press Kit",
        "RecordingStudioPresskits::Podcast" => "Podcast",
        "RecordingStudioPresskits::Quote" => "Quote"
      )
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }

      assert_equal "Press Kit - Create Upload", tools.fetch("PressKit--create_upload")["title"]
      assert_equal "Podcast - Create Upload", tools.fetch("Podcast--create_upload")["title"]
      assert_equal "Quote - Create Upload", tools.fetch("Quote--create_upload")["title"]
    end
  end

  def test_openapi_keeps_a_gem_title_that_already_names_the_type
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Podcast",
        operations: %i[index show],
        capability_actions: %i[add],
        openapi: { tags: ["Press Kit"] }
      )
      register_named_capability(
        :add,
        summary: "Add this podcast",
        title: "Podcast - Add"
      )

      spec = openapi_with_labels!("RecordingStudioPresskits::Podcast" => "Podcast")
      add = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "Podcast--add" }
      described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Podcast")

      assert_equal "Podcast - Add", add["title"]
      assert_equal "Podcast - Add", described.fetch("capability_actions").first.fetch("title")
    end
  end

  def test_action_docs_name_the_singular_label_without_repeating_it
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      %w[Files Images Identity User].each do |name|
        register_tree_type(
          name,
          operations: %i[index show],
          capability_actions: %i[ping],
          openapi: { tags: ["Media"] }
        )
      end
      register_named_capability(:ping, summary: "Ping this record")

      spec = openapi_with_labels!(
        "Files" => "Files",
        "Images" => "Images",
        "Identity" => "Identity",
        "User" => "User"
      )
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }

      assert_includes tools.fetch("Files--ping")["description"], "Runs on File records (Files)."
      assert_includes tools.fetch("Images--ping")["description"], "Runs on Image records (Images)."
      assert_includes tools.fetch("Identity--ping")["description"], "Runs on Identity records."
      refute_includes tools.fetch("Identity--ping")["description"], "(Identity)"
      assert_includes tools.fetch("User--ping")["description"], "Runs on User records."
      refute_includes tools.fetch("User--ping")["description"], "(User)"
    end
  end

  def test_openapi_uses_a_documented_title_without_a_separator_verbatim
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Files",
        operations: %i[index show],
        capability_actions: %i[create_upload],
        openapi: { tags: ["Press Kit"] }
      )
      register_named_capability(
        :create_upload,
        summary: "Create an upload",
        title: "Upload"
      )

      spec = openapi_with_labels!("RecordingStudioPresskits::Files" => "Files")
      upload = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "Files--create_upload" }

      assert_equal "Upload", upload["title"]
    end
  end

  def test_openapi_uses_an_action_first_title_verbatim
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Podcast",
        operations: %i[index show],
        capability_actions: %i[add],
        openapi: { tags: ["Press Kit"] }
      )
      register_named_capability(
        :add,
        summary: "Add this podcast",
        title: "Add podcast"
      )

      spec = openapi_with_labels!("RecordingStudioPresskits::Podcast" => "Podcast")
      add = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "Podcast--add" }
      described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Podcast")

      assert_equal "Add podcast", add["title"]
      assert_equal "Add podcast", described.fetch("capability_actions").first.fetch("title")
    end
  end

  def test_openapi_singularizes_type_labels_for_files_images_and_podcast_actions
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      %w[Files Images Podcast].each do |name|
        register_tree_type(
          "RecordingStudioPresskits::#{name}",
          operations: %i[index show],
          capability_actions: %i[create_upload attach],
          openapi: { tags: ["Press Kit"] }
        )
      end
      register_named_capability(:create_upload, summary: "Create an upload")
      register_named_capability(:attach, summary: "Attach a file")

      spec = openapi_with_labels!(
        "RecordingStudioPresskits::Files" => "Files",
        "RecordingStudioPresskits::Images" => "Images",
        "RecordingStudioPresskits::Podcast" => "Podcast"
      )
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Files")
      describe_titles = described.fetch("capability_actions").to_h do |action|
        [action.fetch("name"), action.fetch("title")]
      end

      assert_equal "File - Create Upload", tools.fetch("Files--create_upload")["title"]
      assert_equal "File - Attach", tools.fetch("Files--attach")["title"]
      assert_equal "Image - Create Upload", tools.fetch("Images--create_upload")["title"]
      assert_equal "Image - Attach", tools.fetch("Images--attach")["title"]
      assert_equal "Podcast - Create Upload", tools.fetch("Podcast--create_upload")["title"]
      assert_equal "Podcast - Attach", tools.fetch("Podcast--attach")["title"]
      assert_equal tools.fetch("Files--create_upload")["title"],
                   describe_titles.fetch("create_upload")
      assert_equal tools.fetch("Files--attach")["title"],
                   describe_titles.fetch("attach")
    end
  end

  def test_openapi_action_page_includes_registered_description_under_summary
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::Files",
        operations: %i[index show],
        capability_actions: %i[attach],
        openapi: { tags: ["Press Kit"] }
      )
      register_named_capability(
        :attach,
        summary: "Attach a file",
        description: "Signed blob from create_upload, or a list of attachments."
      )

      spec = openapi_with_labels!("RecordingStudioPresskits::Files" => "Files")
      attach = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "Files--attach" }
      page = attach.fetch("description")
      summary_at = page.index("Attach a file")
      description_at = page.index("Signed blob from create_upload, or a list of attachments.")
      tool_at = page.index("Tool: capability_action")

      assert_equal "File - Attach", attach["title"]
      assert_operator description_at, :>, summary_at
      assert_operator tool_at, :>, description_at
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
      tag_names = Array(spec["tags"]).map { |tag| tag["name"] }

      assert_equal [{ "name" => "Host", "tags" => %w[Core] }], spec["x-tagGroups"]
      refute_includes tag_names, "Core"
    end
  end

  def test_openapi_sidebar_orders_groups_and_drops_fallback_buckets
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::ListSection",
        operations: %i[index show],
        capability_actions: %i[ping],
        openapi: { tags: ["Press Kit List Section"] }
      )
      register_tree_type(
        "RecordingStudioPresskits::PressKit",
        operations: %i[index show],
        openapi: { tags: ["Press Kit"] }
      )
      register_tree_type(
        "Workspace",
        operations: %i[index show],
        capability_actions: %i[grant_access]
      )
      register_named_capability(:ping, summary: "Ping")
      register_named_capability(:grant_access, summary: "Grant access")
      RecordingStudioApi.register_endpoint(
        :zebra,
        http_verb: :get,
        path: "zebra",
        openapi: { summary: "Zebra", tags: ["Zebra"] },
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        openapi: { summary: "Ping" },
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :loose_end,
        http_verb: :get,
        path: "loose_end",
        openapi: { summary: "Loose" },
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :workspace_ping,
        http_verb: :get,
        path: "workspaces/:id/ping",
        recordable_type: "Workspace",
        openapi: { summary: "Workspace ping" },
        handler: ->(_context) { { ok: true } }
      )
      include_api_endpoints(tree: true)

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      protocol_names = RecordingStudioMcp::Tools.definitions(api: :public).map { |tool| tool[:name] }
      press_kit = tag_names.index("Press Kit")
      press_kit_list = tag_names.index("Press Kit List Section")

      assert_equal ["Overview"], tools.fetch("list")["tags"]
      assert_equal ["Overview"], tools.fetch("ping")["tags"]
      assert_equal ["Press Kit List Section"], tools.fetch("ListSection--ping")["tags"]
      assert_equal ["Workspace"], tools.fetch("Workspace--grant_access")["tags"]
      assert_equal ["Workspace"], tools.fetch("workspace_ping")["tags"]
      assert_equal ["Other tools"], tools.fetch("loose_end")["tags"]
      assert_equal ["Zebra"], tools.fetch("zebra")["tags"]
      assert_operator press_kit, :<, press_kit_list
      assert_equal [], tag_names[(press_kit + 1)...press_kit_list]
      assert_equal "Overview", tag_names.first
      refute_includes tag_names, "Core"
      refute_includes tag_names, "Tools"
      assert_equal "Other tools", tag_names.last
      assert_equal ordered_sidebar_names(tag_names), tag_names
      %w[Endpoints Tools Resources].each { |name| refute_includes tag_names, name }
      refute spec["x-mcp"].key?("resources")
      refute spec["x-mcp"].key?("resourceTemplates")
      refute spec.key?("x-tagGroups")
      refute_includes protocol_names, "Workspace--grant_access"
      assert_includes protocol_names, "list"
      assert_includes protocol_names, "ping"
    end
  end

  def test_describe_and_docs_prefer_per_type_action_copy
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "Podcast",
        operations: %i[index show],
        capability_actions: %i[add],
        openapi: { tags: ["Shows"] }
      )
      register_tree_type(
        "Quote",
        operations: %i[index show],
        capability_actions: %i[add],
        openapi: { tags: ["Shows"] }
      )
      RecordingStudioApi.register_capability_action(
        :add,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } },
        openapi: { summary: "Shared summary", description: "Shared description." },
        openapi_for: lambda { |type:, action:|
          next {} unless type.to_s == "Quote" && action.present?

          { summary: "Quote summary", description: "Quote description." }
        }
      )

      spec = openapi_with_labels!("Podcast" => "Podcast", "Quote" => "Quote")
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      quote = catalog.documentation_type("Quote").fetch("capability_actions").first
      podcast = catalog.documentation_type("Podcast").fetch("capability_actions").first
      quote_page = tools.fetch("Quote--add").fetch("description")
      podcast_page = tools.fetch("Podcast--add").fetch("description")

      assert_equal "Quote summary", quote.fetch("summary")
      assert_equal "Quote description.", quote.fetch("description")
      assert_equal "Shared summary", podcast.fetch("summary")
      assert_equal "Shared description.", podcast.fetch("description")
      assert_includes quote_page, "Quote summary"
      assert_includes quote_page, "Quote description."
      refute_includes quote_page, "Shared summary"
      refute_includes quote_page, "Shared description."
      assert_includes podcast_page, "Shared summary"
      assert_includes podcast_page, "Shared description."
    end
  end

  def test_openapi_uses_each_types_documented_action_title
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "Podcast",
        operations: %i[index show],
        capability_actions: %i[add],
        openapi: { tags: ["Shows"] }
      )
      register_tree_type(
        "Quote",
        operations: %i[index show],
        capability_actions: %i[add],
        openapi: { tags: ["Shows"] }
      )
      RecordingStudioApi.register_capability_action(
        :add,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } },
        openapi: { summary: "Add a record", title: "Add podcast" },
        openapi_for: lambda { |type:, action:|
          titles = { "Podcast" => "Add podcast", "Quote" => "Add a quote" }
          title = titles[type.to_s]
          action.present? && title ? { title: title } : {}
        }
      )

      spec = openapi_with_labels!("Podcast" => "Podcast", "Quote" => "Quote")
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("Quote")

      assert_equal "Add podcast", tools.fetch("Podcast--add")["title"]
      assert_equal "Add a quote", tools.fetch("Quote--add")["title"]
      assert_equal "Add a quote", described.fetch("capability_actions").first.fetch("title")
    end
  end

  def test_openapi_suffixes_a_capability_action_sidebar_group
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "Video",
        operations: %i[index show],
        capability_actions: %i[shelve ping],
        openapi: { tags: ["Video"] }
      )
      register_tree_type(
        "Clip",
        operations: %i[index show],
        capability_actions: %i[shelve],
        openapi: { tags: ["Clip"] }
      )
      register_ping_capability
      RecordingStudioApi.register_capability_action(
        :shelve,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } },
        openapi: { summary: "Shelve a record", tag_suffix: "Trash" },
        openapi_for: lambda { |type:, action:|
          type.to_s == "Clip" && action.present? ? { tag_suffix: "Archive" } : {}
        }
      )

      spec = openapi_with_labels!("Video" => "Video", "Clip" => "Clip")
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      video = tag_names.index("Video")
      video_trash = tag_names.index("Video Trash")

      assert_equal ["Video Trash"], tools.fetch("Video--shelve")["tags"]
      assert_equal ["Clip Archive"], tools.fetch("Clip--shelve")["tags"]
      assert_equal ["Video"], tools.fetch("Video--ping")["tags"]
      refute_includes tools.fetch("Video--shelve").keys, "tag_suffix"
      refute_includes spec.to_json, "tag_suffix"
      assert_operator video, :<, video_trash
      assert_equal [], tag_names[(video + 1)...video_trash]
    end
  end

  def tool_lines(text)
    text.to_s.scan(/^Tool: .+$/)
  end

  def ordered_sidebar_names(names)
    rest = names - ["Overview", "Other tools"]
    head = names.include?("Overview") ? ["Overview"] : []
    [*head, *rest.sort, *("Other tools" if names.include?("Other tools"))]
  end

  def overview_for(instructions)
    "#{instructions}\n\nA view-only connection gets the same text minus the Make changes part."
  end

  def openapi_with_credit_label!
    openapi_with_labels!("RecordingStudioPresskits::Credit" => "Credit")
  end

  def openapi_with_labels!(labels)
    store = RecordingStudio::Labels.formatters.fetch(:type_label)
    previous = labels.keys.index_with { |type| store[type] }
    labels.each do |type, label|
      RecordingStudio::Labels.register_formatter(type, type_label: ->(*) { label })
    end
    RecordingStudioMcp::Documentation.openapi(api: :public)
  ensure
    previous&.each do |type, value|
      if value
        store[type] = value
      else
        store.delete(type)
      end
    end
  end

  def stub_allowed_parents(map, &)
    original = RecordingStudio.method(:allowed_parent_types_for)
    RecordingStudio.stub(:allowed_parent_types_for, lambda { |type|
      name = type.to_s
      map.key?(name) ? Array(map.fetch(name)) : original.call(type)
    }, &)
  end

  def register_named_capability(name, summary:, title: nil, description: nil, input_contract: nil)
    openapi = { summary: summary }
    openapi[:title] = title if title
    openapi[:description] = description if description
    attrs = {
      capability: :accessible,
      handler: ->(_context) { { json: { ok: true } } },
      openapi: openapi
    }
    attrs[:input_contract] = input_contract if input_contract
    RecordingStudioApi.register_capability_action(name, **attrs)
  end
end
