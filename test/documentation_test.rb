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
      assert_includes mcp["instructions"],
                      "Call describe for the type paragraph, included tools, skills, relationships, " \
                      "allowed parents, writable fields, and available actions"
      assert_includes names, "list"
      assert_includes names, "describe"
      assert_includes names, "ping"
      refute_includes names, "Folder--ping"
      assert_docs_tools_match_live spec
      folder = spec.fetch("tags").find { |tag| tag["name"] == "Folder" }.fetch("description")
      assert_includes folder, "Tool: create with type `Folder`"
      assert_includes folder, "Tool: capability_action with type `Folder`."
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
      refute_includes tools.keys, "Folder--ping"
      refute tools.fetch("list").key?("x-mcp-docs-only")
      assert_docs_tools_match_live spec
      folder = spec.fetch("tags").find { |tag| tag["name"] == "Folder" }.fetch("description")
      assert_includes folder, "Tool: list with type `Folder`"
      assert_includes folder, "Tool: create with type `Folder`"
      assert_includes folder, "Tool: capability_action with type `Folder`."
      refute_includes folder, "Allowed operations:"
      refute_includes folder, "style"
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
      names = docs_tool_names(spec)
      press_kit = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }

      refute_includes spec.dig("components", "schemas").keys, "RecordingStudioPresskits::Credit"
      refute_includes spec.dig("components", "schemas").keys, "Folder"
      refute_includes names, "Credit--ping"
      assert_docs_tools_match_live spec
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
        names = docs_tool_names(spec)
        press_intro = spec.fetch("tags").find { |tag| tag["name"] == "PressKit" }.fetch("description")
        note_intro = spec.fetch("tags").find { |tag| tag["name"] == "Note" }.fetch("description")
        message_intro = spec.fetch("tags").find { |tag| tag["name"] == "Message" }.fetch("description")

        assert_docs_tools_match_live spec
        refute_includes names, "PressKit--ping"
        refute_includes names, "PressKit--list"
        refute_includes names, "Note--list"
        refute_includes names, "Message--show"
        assert_includes press_intro, "Tool: list with type `PressKit` and parent_id (the press center id)"
        assert_includes press_intro, "Tool: show with type `PressKit` and id"
        create_line = "Tool: create with type `PressKit`, parent_id, writable fields at the top level, " \
                      "and optional idempotency_key"
        assert_includes press_intro, create_line
        assert_includes press_intro, "Tool: update with type `PressKit`, id, and writable fields"
        assert_includes press_intro, "Tool: delete with type `PressKit` and id"
        assert_includes press_intro, "Tool: capability_action with type `PressKit`."
        refute_includes press_intro, "RecordingStudioPresskits::PressKit"
        assert_includes note_intro, "Tool: list with type `Note` and parent_id"
        refute_includes note_intro, "(the "
        refute_includes note_intro, "Tool: create"
        refute_includes note_intro, "Tool: update"
        refute_includes note_intro, "Tool: delete"
        assert_includes message_intro, "Tool: show with type `Message` and id"
        refute_includes message_intro, "Tool: list"
        refute_includes message_intro, "Tool: delete"
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
        intro = spec.fetch("tags").find { |tag| tag["name"] == "Page" }.fetch("description")

        refute_includes docs_tool_names(spec), "Page--ping"
        assert_docs_tools_match_live spec
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
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Support" }.fetch("description")

      refute_includes names, "Support--search"
      assert_docs_tools_match_live spec
      assert_includes intro, "Tool: list with type `Support`"
      assert_includes intro, "Tool: show with type `Support` and id"
      assert_includes intro, "Tool: capability_action with type `Support`."
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
      names = docs_tool_names(spec)
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Identity" }.fetch("description")
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Identity")
      remove = described.fetch("capability_actions").find { |action| action["name"] == "identity_remove_image" }

      refute_includes names, "Identity--identity_remove_image"
      refute_includes names, "Identity--ping"
      assert_docs_tools_match_live spec
      assert_includes remove.fetch("idempotency_key"), "creates: true"
      assert_equal 1, intro.scan("Tool: list with type `Identity`").size
      assert_includes intro, "Tool: delete with type `Identity` and id"
      assert_includes intro, "Tool: capability_action with type `Identity`."
      assert_includes intro, "Capability actions:"
      assert_includes intro, "- identity_remove_image. #{remove.fetch('idempotency_key')}"
      assert_includes intro, "- ping"
      refute_includes intro, "- ping."
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

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Folder")
      add = described.fetch("capability_actions").find { |action| action["name"] == "add_file" }
      peek = described.fetch("capability_actions").find { |action| action["name"] == "peek" }

      refute_includes docs_tool_names(spec), "Folder--add_file"
      refute_includes docs_tool_names(spec), "Folder--peek"
      assert_docs_tools_match_live spec
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Folder" }.fetch("description")

      assert_includes add.fetch("idempotency_key"), "creates: true"
      assert peek.fetch("idempotency_key")
      assert_includes intro, "- add_file. #{add.fetch('idempotency_key')}"
      assert_includes intro, "- peek"
      refute_includes intro, "- peek."
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

  def test_type_docs_section_matches_describe_tools_parents_and_relationships
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type(
        "Folder",
        operations: %i[index show],
        capability_actions: %i[ping],
        description: "A folder of notes.",
        writable_attributes: %i[name],
        output_keys: %i[name],
        relationships: {
          pages: {
            source: :children,
            child_type: "Page",
            many: true,
            serializer: ->(*) { { title: "Title" } },
            output_keys: %i[title],
            description: "Pages in this folder",
            limit: 20
          }
        }
      )
      register_tree_type("Page", operations: %i[index show])
      ping_folder = RecordingStudioMcp.tool_name("Folder", :ping)
      RecordingStudioMcp.register_tool(
        name: ping_folder,
        type: "Folder",
        action: :ping,
        title: "Ping folder",
        description: "Ping a folder.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: [ping_folder])
      parents = ->(type) { type.to_s == "Folder" ? %w[Workspace] : [] }
      spec = nil
      described = nil
      RecordingStudio.stub(:root_allowed?, false) do
        RecordingStudio.stub(:allowed_parent_types_for, parents) do
          spec = RecordingStudioMcp::Documentation.openapi(api: :public)
          described = RecordingStudioMcp::Catalog.new(api: :public).describe("Folder")
        end
      end
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Folder" }.fetch("description")

      assert_equal "A folder of notes.", described.fetch("description")
      assert_includes intro, described.fetch("description")
      described.fetch("tools").each { |name| assert_includes intro, "Tool: #{name}" }
      assert_includes intro, "Capability actions:"
      assert_includes intro, "- ping"
      assert_includes described.fetch("tools"), "list"
      assert_includes described.fetch("tools"), "show"
      assert_includes described.fetch("tools"), ping_folder
      refute_includes described.fetch("tools"), "delete"
      refute_includes intro, "Tool: delete"
      assert_equal false, described.dig("parent", "root")
      assert_equal ["Workspace"], described.dig("parent", "allowed_parent_types")
      assert_includes intro, "Parents: root false. allowed parent types Workspace."
      pages = described.fetch("relationships").find { |rel| rel["name"] == "pages" }

      assert_equal "Pages in this folder", pages.fetch("description")
      assert_includes intro, "pages, children, Page, many"
      assert_includes intro, pages.fetch("description")
    end
  end

  def test_docs_tools_match_tools_list_on_public_and_operations
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :operations
      register_ping_capability
      register_tree_type("Page", operations: %i[index show create update], capability_actions: %i[ping])
      register_tree_type(
        "SupportPage",
        api: :operations,
        operations: %i[index show],
        allow_sensitive: true
      )
      RecordingStudioApi.register_endpoint(
        :ops_ping,
        api: :operations,
        http_verb: :get,
        path: "ping",
        openapi: { summary: "Ops ping" },
        handler: ->(_context) { { ok: true } }
      )
      include_api_endpoints(tree: true)
      include_api_endpoints(api: :operations, tree: true, allow_sensitive: true)

      public_spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      ops_spec = RecordingStudioMcp::Documentation.openapi(api: :operations)

      assert_docs_tools_match_live public_spec
      assert_docs_tools_match_live ops_spec, api: :operations
      refute_includes docs_tool_names(public_spec), "Page--ping"
      assert_includes docs_tool_names(ops_spec), "ops_ping"
      refute_includes docs_tool_names(public_spec), "ops_ping"
      refute_includes docs_tool_names(ops_spec), "create"
    end
  end

  def test_press_kit_section_lists_live_create_and_named_tools_not_capability_actions
    with_isolated_api_configuration do
      register_named_capability(:create_section, summary: "Create a section")
      register_named_capability(:set_visibility, summary: "Set visibility")
      register_named_capability(:publish, summary: "Publish this kit")
      register_named_capability(:unpublish, summary: "Unpublish this kit")
      register_named_capability(:attach, summary: "Attach a file")
      register_named_capability(:create_upload, summary: "Create an upload")
      register_named_capability(:import_attachment, summary: "Import an attachment")
      register_tree_type(
        "RecordingStudioPresskits::PressKit",
        operations: %i[index show create update],
        capability_actions: %i[create_section set_visibility publish unpublish attach create_upload import_attachment],
        openapi: { tags: ["Press Kit"] }
      )
      create_section = RecordingStudioMcp.tool_name("RecordingStudioPresskits::PressKit", :create_section)
      set_visibility = RecordingStudioMcp.tool_name("RecordingStudioPresskits::PressKit", :set_visibility)
      RecordingStudioMcp.register_tool(
        name: create_section,
        type: "RecordingStudioPresskits::PressKit",
        action: :create_section,
        title: "Create a section",
        description: "Add a section to this press kit.",
        input: {},
        output: "ok"
      )
      RecordingStudioMcp.register_tool(
        name: set_visibility,
        type: "RecordingStudioPresskits::PressKit",
        action: :set_visibility,
        title: "Set visibility",
        description: "Set who can see this press kit.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: [create_section, set_visibility])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      names = docs_tool_names(spec)
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }.fetch("description")
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("PressKit")

      assert_docs_tools_match_live spec
      assert_includes described.fetch("tools"), "create"
      assert_includes described.fetch("tools"), create_section
      assert_includes intro, "Tool: create with type `PressKit`"
      assert_includes intro, "Tool: list with type `PressKit`"
      assert_includes intro, "Tool: #{create_section}"
      assert_includes intro, "Tool: #{set_visibility}"
      assert_includes intro, "Tool: capability_action with type `PressKit`."
      assert_includes intro, "Capability actions:"
      %w[create_section set_visibility publish unpublish attach create_upload import_attachment].each do |name|
        assert_includes intro, "- #{name}"
      end
      assert_equal ["Press Kit"], tools.fetch(create_section)["tags"]
      assert_equal ["Press Kit"], tools.fetch(set_visibility)["tags"]
      assert_equal ["Overview"], tools.fetch("create")["tags"]
      %w[PressKit--publish PressKit--unpublish PressKit--attach PressKit--create_upload
         PressKit--import_attachment].each do |name|
        refute_includes names, name
      end
      refute_includes intro, "Tool: PressKit--publish"
    end
  end

  def test_type_docs_section_omits_delete_when_describe_omits_it
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index show create update])
      register_tree_type("Trash", operations: %i[index show create update destroy])
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      described = catalog.describe("Page")
      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Page" }.fetch("description")
      trash = spec.fetch("tags").find { |tag| tag["name"] == "Trash" }.fetch("description")

      refute_includes described.fetch("tools"), "delete"
      refute_includes intro, "Tool: delete"
      assert_includes catalog.describe("Trash").fetch("tools"), "delete"
      assert_includes trash, "Tool: delete with type `Trash` and id"
    end
  end

  def test_sidebar_omits_a_tag_when_describe_has_nothing_to_show
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
      RecordingStudioMcp.register_type(type: "EmptyShelf", description: "")
      publish_mcp_server(:public, tools: [])
      spec = RecordingStudio.stub(:root_allowed?, false) do
        RecordingStudio.stub(:allowed_parent_types_for, ->(*) { [] }) do
          lines = RecordingStudioMcp::Documentation::Openapi::TypeOperationLines
          lines.stub(:section_for, "") { RecordingStudioMcp::Documentation.openapi(api: :public) }
        end
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
      assert_equal 2, press_kit["description"].scan("Credits on a press kit.").size
      assert_includes press_kit["description"], "Type: `Credit`"
      assert_includes press_kit["description"], "Type: `KitSection`"
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
      assert_includes press_kit["description"], "Credits on a press kit."
      assert_includes press_kit["description"], "Sections in a press kit."
      assert_includes press_kit["description"], "Type: `Credit`"
      assert_includes press_kit["description"], "Type: `KitSection`"
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
      names = docs_tool_names(spec)
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }.fetch("description")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      credits = catalog.documentation_type("RecordingStudioPresskits::CreditsSection")
      titles = credits.fetch("capability_actions").map { |action| action["title"] }
      schemas = spec.dig("components", "schemas")

      assert_docs_tools_match_live spec
      %w[CreditsSection--add_credit CreditsSection--reorder_credits CreditLine--remove_credit].each do |name|
        refute_includes names, name
      end
      assert_includes titles, "Credits section - Add Credit"
      assert_includes intro, "Tool: capability_action with type `CreditsSection`."
      assert_includes intro, "Tool: list with type `Credit`"
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
      names = docs_tool_names(spec)
      intro = spec.fetch("tags").find { |tag| tag["name"] == "Galleries" }.fetch("description")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      add = catalog.documentation_type("GallerySection").fetch("capability_actions").first
      schemas = spec.dig("components", "schemas")

      assert_docs_tools_match_live spec
      %w[Gallery--publish GallerySection--add_slide GallerySlide--remove_slide].each do |name|
        refute_includes names, name
      end
      assert_equal "Gallery section - Add Slide", add.fetch("title")
      assert_includes intro, "Tool: capability_action with type `GallerySection`."
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
      ping_folder = RecordingStudioMcp.tool_name("Folder", :ping)
      RecordingStudioMcp.register_tool(
        name: ping_folder,
        type: "Folder",
        action: :ping,
        title: "Ping folder",
        description: "Ping a folder.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: [ping_folder])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      names = spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }

      assert_docs_tools_match_live spec
      assert_equal 1, names.count(ping_folder)
      refute_includes names, "Folder--ping"
      refute_includes names, "Page--ping"
      refute tools.fetch(ping_folder)["x-mcp-docs-only"]
      assert_equal ["Folder"], tools.fetch(ping_folder)["tags"]
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
      add_file = RecordingStudioMcp.tool_name("RecordingStudioPresskits::Files", :add_file)
      RecordingStudioMcp.register_tool(
        name: add_file,
        type: "RecordingStudioPresskits::Files",
        action: :add_file,
        title: "Add a file",
        description: "Add a file to this section.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: [add_file])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      add = tools.fetch(add_file)

      assert_docs_tools_match_live spec
      assert_equal ["Press Kit"], add["tags"]
      refute add["x-mcp-docs-only"]
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

      titles = nil
      spec = openapi_with_labels!(
        "RecordingStudioPresskits::PressKit" => "Press Kit",
        "RecordingStudioPresskits::Podcast" => "Podcast",
        "RecordingStudioPresskits::Quote" => "Quote"
      ) do
        catalog = RecordingStudioMcp::Catalog.new(api: :public)
        titles = %w[PressKit Podcast Quote].to_h do |name|
          type = "RecordingStudioPresskits::#{name}"
          [name, catalog.documentation_type(type).fetch("capability_actions").first.fetch("title")]
        end
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "PressKit--create_upload"
      assert_equal "Press Kit - Create Upload", titles.fetch("PressKit")
      assert_equal "Podcast - Create Upload", titles.fetch("Podcast")
      assert_equal "Quote - Create Upload", titles.fetch("Quote")
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

      described = nil
      spec = openapi_with_labels!("RecordingStudioPresskits::Podcast" => "Podcast") do
        described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Podcast")
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Podcast--add"
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
      names = docs_tool_names(spec)

      assert_docs_tools_match_live spec
      %w[Files--ping Images--ping Identity--ping User--ping].each { |name| refute_includes names, name }
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

      described = nil
      spec = openapi_with_labels!("RecordingStudioPresskits::Files" => "Files") do
        described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Files")
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Files--create_upload"
      assert_equal "Upload", described.fetch("capability_actions").first.fetch("title")
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

      described = nil
      spec = openapi_with_labels!("RecordingStudioPresskits::Podcast" => "Podcast") do
        described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Podcast")
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Podcast--add"
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

      files = images = podcast = nil
      spec = openapi_with_labels!(
        "RecordingStudioPresskits::Files" => "Files",
        "RecordingStudioPresskits::Images" => "Images",
        "RecordingStudioPresskits::Podcast" => "Podcast"
      ) do
        catalog = RecordingStudioMcp::Catalog.new(api: :public)
        titles = lambda do |type|
          catalog.documentation_type(type).fetch("capability_actions").to_h do |action|
            [action.fetch("name"), action.fetch("title")]
          end
        end
        files = titles.call("RecordingStudioPresskits::Files")
        images = titles.call("RecordingStudioPresskits::Images")
        podcast = titles.call("RecordingStudioPresskits::Podcast")
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Files--create_upload"
      assert_equal "File - Create Upload", files.fetch("create_upload")
      assert_equal "File - Attach", files.fetch("attach")
      assert_equal "Image - Create Upload", images.fetch("create_upload")
      assert_equal "Image - Attach", images.fetch("attach")
      assert_equal "Podcast - Create Upload", podcast.fetch("create_upload")
      assert_equal "Podcast - Attach", podcast.fetch("attach")
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

      attach = nil
      spec = openapi_with_labels!("RecordingStudioPresskits::Files" => "Files") do
        described = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("RecordingStudioPresskits::Files")
        attach = described.fetch("capability_actions").first
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Files--attach"
      assert_equal "File - Attach", attach.fetch("title")
      assert_equal "Attach a file", attach.fetch("summary")
      assert_equal "Signed blob from create_upload, or a list of attachments.", attach.fetch("description")
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
      names = docs_tool_names(spec)
      press_kit = tag_names.index("Press Kit")
      press_kit_list = tag_names.index("Press Kit List Section")

      assert_docs_tools_match_live spec
      assert_equal ["Overview"], tools.fetch("list")["tags"]
      assert_equal ["Overview"], tools.fetch("ping")["tags"]
      refute_includes names, "ListSection--ping"
      refute_includes names, "Workspace--grant_access"
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
      assert_includes names, "list"
      assert_includes names, "ping"
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

      quote = podcast = nil
      spec = openapi_with_labels!("Podcast" => "Podcast", "Quote" => "Quote") do
        catalog = RecordingStudioMcp::Catalog.new(api: :public)
        quote = catalog.documentation_type("Quote").fetch("capability_actions").first
        podcast = catalog.documentation_type("Podcast").fetch("capability_actions").first
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Quote--add"
      refute_includes docs_tool_names(spec), "Podcast--add"
      assert_equal "Quote summary", quote.fetch("summary")
      assert_equal "Quote description.", quote.fetch("description")
      assert_equal "Shared summary", podcast.fetch("summary")
      assert_equal "Shared description.", podcast.fetch("description")
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

      podcast = quote = nil
      spec = openapi_with_labels!("Podcast" => "Podcast", "Quote" => "Quote") do
        catalog = RecordingStudioMcp::Catalog.new(api: :public)
        podcast = catalog.documentation_type("Podcast").fetch("capability_actions").first
        quote = catalog.documentation_type("Quote").fetch("capability_actions").first
      end

      assert_docs_tools_match_live spec
      refute_includes docs_tool_names(spec), "Podcast--add"
      refute_includes docs_tool_names(spec), "Quote--add"
      assert_equal "Add podcast", podcast.fetch("title")
      assert_equal "Add a quote", quote.fetch("title")
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

      shelve_video = RecordingStudioMcp.tool_name("Video", :shelve)
      shelve_clip = RecordingStudioMcp.tool_name("Clip", :shelve)
      ping_video = RecordingStudioMcp.tool_name("Video", :ping)
      [
        ["Video", :shelve, shelve_video],
        ["Clip", :shelve, shelve_clip],
        ["Video", :ping, ping_video]
      ].each do |type, action, name|
        RecordingStudioMcp.register_tool(
          name: name,
          type: type,
          action: action,
          title: name,
          description: name,
          input: {},
          output: "ok"
        )
      end
      ensure_tree_server(:public, extra_tools: [shelve_video, shelve_clip, ping_video])

      spec = openapi_with_labels!("Video" => "Video", "Clip" => "Clip")
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      video = tag_names.index("Video")
      video_trash = tag_names.index("Video Trash")

      assert_docs_tools_match_live spec
      assert_equal ["Video Trash"], tools.fetch(shelve_video)["tags"]
      assert_equal ["Clip Archive"], tools.fetch(shelve_clip)["tags"]
      assert_equal ["Video"], tools.fetch(ping_video)["tags"]
      refute_includes tools.fetch(shelve_video).keys, "tag_suffix"
      refute_includes spec.to_json, "tag_suffix"
      assert_operator video, :<, video_trash
      assert_equal [], tag_names[(video + 1)...video_trash]
    end
  end

  def tool_lines(text)
    text.to_s.scan(/^Tool: .+$/)
  end

  def live_tool_names(api: :public)
    RecordingStudioMcp::Tools.definitions(api: api).map { |tool| tool[:name].to_s }
  end

  def docs_tool_names(spec)
    spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
  end

  def assert_docs_tools_match_live(spec, api: :public)
    assert_equal live_tool_names(api: api).sort, docs_tool_names(spec).sort
    spec.dig("x-mcp", "tools").each do |tool|
      refute tool["x-mcp-docs-only"], "#{tool['name']} must not be docs-only"
    end
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
    spec = RecordingStudioMcp::Documentation.openapi(api: :public)
    yield spec if block_given?
    spec
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
