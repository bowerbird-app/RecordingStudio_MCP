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

      assert_equal "3.1.0", spec["openapi"]
      assert_equal "Public MCP", spec.dig("info", "title")
      refute_empty spec.dig("info", "description")
      refute_equal spec.dig("info", "description"), mcp["instructions"]
      assert_includes spec.dig("info", "description"), "## Authentication"
      assert_includes mcp["instructions"], "Call describe before create"
      assert_includes names, "list"
      assert_includes names, "describe"
      assert_includes names, "ping"
      assert_includes names, "Folder--ping"
      assert_equal ["TypeName"], schemas.keys
      refute_includes schemas.keys, "Folder"
      refute_includes schemas.keys, "Page"
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
      schemas = spec.dig("components", "schemas")
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
      refute_includes ping_tool["description"], "Tool name:"
      refute_includes ping_tool["description"], "Runs on a "
      refute_includes ping_tool["description"], "Type: `Folder`"
      refute_includes ping_tool["description"], "Allowed operations:"
      refute_includes ping_tool["description"], "Writable fields:"
      refute_includes ping_tool["description"], "A folder record in this workspace."
      assert_includes ping_tool["description"], "Tool: capability_action with type `Folder` and action `ping`"
      refute_includes ping_tool["description"], "style"
      refute_includes ping_tool["description"], "reject_unknown"
      refute ping_tool.key?("tags")
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
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }
      press_kit = spec.fetch("tags").find { |tag| tag["name"] == "Press Kit" }
      ping_tool = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "RecordingStudioPresskits::Credit--ping" }
      ping_description = ping_tool.fetch("description")
      type_description_at = ping_description.index("Credits on a press kit.")
      tool_at = ping_description.index("Tool: capability_action")

      refute_includes spec.dig("components", "schemas").keys, "RecordingStudioPresskits::Credit"
      refute_includes spec.dig("components", "schemas").keys, "Folder"
      assert_equal "Credit - Ping", ping_tool["title"]
      assert_equal ["Press Kit"], ping_tool["tags"]
      assert_includes ping_tool["description"], "Credits on a press kit."
      refute_includes ping_tool["description"], "Tool name:"
      refute_includes ping_tool["description"], "Runs on a "
      refute_includes ping_tool["description"], "Type: `RecordingStudioPresskits::Credit`"
      assert_operator tool_at, :>, type_description_at
      refute_includes ping_tool["description"], "Allowed operations:"
      refute_includes ping_tool["description"], "Writable fields:"
      assert_includes ping_tool["description"],
                      "Tool: capability_action with type `RecordingStudioPresskits::Credit` and action `ping`"
      assert_equal "Credits on a press kit.", press_kit["description"]
      assert_includes tag_names, "Press Kit"
      refute_includes tag_names, "Press kits"
      refute_includes tag_names, "Types"
      assert_equal 1, tag_names.count("Press Kit")
      assert_equal tag_names.uniq, tag_names
      refute spec.key?("x-tagGroups")
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

      assert_equal "Credits on a press kit.", press_kit["description"]
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
      refute press_kit.key?("description")
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
        openapi: {
          tags: ["Press Kit"],
          description: "A Credits section lists the people credited on a press kit. It lives under a kit section."
        }
      )
      register_named_capability(
        :add_credit,
        summary: "Add a workspace credit to this section",
        description: "Add a named person from this workspace to this Credits section.",
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

      assert_equal [
        "Credits section - Add Credit",
        "Credits section - Reorder Credits",
        "credit line - Remove Credit"
      ], titles
      refute_includes protocol_names, "RecordingStudioPresskits::CreditsSection--add_credit"
      add = tools.fetch("RecordingStudioPresskits::CreditsSection--add_credit")
      reorder = tools.fetch("RecordingStudioPresskits::CreditsSection--reorder_credits")
      remove = tools.fetch("RecordingStudioPresskits::CreditLine--remove_credit")
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
      add_description = add["description"]
      add_action_at = add_description.index("Add a named person from this workspace to this Credits section.")
      add_type_at = add_description.index(
        "A Credits section lists the people credited on a press kit. It lives under a kit section."
      )
      add_tool_at = add_description.index("Tool: capability_action")
      refute_includes add_description, "Tool name:"
      refute_includes add_description, "Runs on a "
      refute_includes add_description, "Type: `RecordingStudioPresskits::CreditsSection`"
      refute_includes add["description"], "Allowed operations:"
      refute_includes add["description"], "Writable fields:"
      refute_includes add_description, "Add a workspace credit to this section"
      assert_operator add_type_at, :>, add_action_at
      assert_operator add_tool_at, :>, add_type_at
      assert_includes add["description"],
                      "Tool: capability_action with type `RecordingStudioPresskits::CreditsSection` " \
                      "and action `add_credit`"
      refute_includes add["description"], "credit_id"
      refute_includes add["description"], "reject_unknown"
      assert_includes reorder["description"], "Reorder credits in this section"
      refute_includes remove["description"], "Runs on a "
      refute_includes remove["description"], "Type: `RecordingStudioPresskits::CreditLine`"
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
      refute_includes publish["description"], "Runs on a "
      assert_equal "Gallery section - Add Slide", add["title"]
      assert_equal ["Galleries"], add["tags"]
      refute_includes add["description"], "Runs on a "
      refute_includes add["description"], "Type: `GallerySection`"
      refute_includes add["description"], "Allowed operations:"
      refute_includes add["description"], "Writable fields:"
      assert_includes add["description"], "Add a slide to this section"
      assert_includes add["description"],
                      "Tool: capability_action with type `GallerySection` and action `add_slide`"
      assert_equal "Gallery slide - Remove Slide", remove["title"]
      assert_equal ["Galleries"], remove["tags"]
      refute_includes remove["description"], "Runs on a "
      refute_includes protocol_names, "GallerySection--add_slide"
      assert_equal ["TypeName"], schemas.keys
      refute_includes schemas.keys, "Gallery"
      refute_includes schemas.keys, "GallerySection"
      refute_includes schemas.keys, "GallerySlide"
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
      add = tools.fetch("RecordingStudioPresskits::Files--add_file")

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

      assert_equal "Press Kit - Create Upload", tools.fetch("RecordingStudioPresskits::PressKit--create_upload")["title"]
      assert_equal "Podcast - Create Upload", tools.fetch("RecordingStudioPresskits::Podcast--create_upload")["title"]
      assert_equal "Quote - Create Upload", tools.fetch("RecordingStudioPresskits::Quote--create_upload")["title"]
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
      add = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "RecordingStudioPresskits::Podcast--add" }
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("RecordingStudioPresskits::Podcast")

      assert_equal "Podcast - Add", add["title"]
      assert_equal "Podcast - Add", described.fetch("capability_actions").first.fetch("title")
    end
  end

  def test_openapi_prefixes_a_type_neutral_upload_title
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
      upload = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "RecordingStudioPresskits::Files--create_upload" }

      assert_equal "File - Upload", upload["title"]
    end
  end

  def test_openapi_prefixes_a_short_openapi_title_with_the_singular_type
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "RecordingStudioPresskits::ListSection",
        operations: %i[index show],
        capability_actions: %i[remove_item],
        openapi: { tags: ["Press Kit"] }
      )
      register_named_capability(
        :remove_item,
        summary: "Remove a row from this list",
        title: "Remove List Item"
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      remove = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "RecordingStudioPresskits::ListSection--remove_item" }

      assert_equal "List section - Remove List Item", remove["title"]
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
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("RecordingStudioPresskits::Files")
      describe_titles = described.fetch("capability_actions").to_h do |action|
        [action.fetch("name"), action.fetch("title")]
      end

      assert_equal "File - Create Upload", tools.fetch("RecordingStudioPresskits::Files--create_upload")["title"]
      assert_equal "File - Attach", tools.fetch("RecordingStudioPresskits::Files--attach")["title"]
      assert_equal "Image - Create Upload", tools.fetch("RecordingStudioPresskits::Images--create_upload")["title"]
      assert_equal "Image - Attach", tools.fetch("RecordingStudioPresskits::Images--attach")["title"]
      assert_equal "Podcast - Create Upload", tools.fetch("RecordingStudioPresskits::Podcast--create_upload")["title"]
      assert_equal "Podcast - Attach", tools.fetch("RecordingStudioPresskits::Podcast--attach")["title"]
      assert_equal tools.fetch("RecordingStudioPresskits::Files--create_upload")["title"],
                   describe_titles.fetch("create_upload")
      assert_equal tools.fetch("RecordingStudioPresskits::Files--attach")["title"],
                   describe_titles.fetch("attach")
    end
  end

  def test_openapi_action_page_shows_access_from_the_registered_role
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "Folder",
        operations: %i[index show],
        capability_actions: %i[peek rename lock stats],
        openapi: { description: "A folder record in this workspace." }
      )
      register_capability_with_role(:peek, summary: "Peek at this folder", role: :view)
      register_capability_with_role(:rename, summary: "Rename this folder", role: :edit)
      register_capability_with_role(:lock, summary: "Lock this folder", role: :admin)
      register_capability_with_role(:stats, summary: "Folder stats", role: nil, scope: :collection)
      RecordingStudioApi.register_endpoint(
        :health,
        http_verb: :get,
        path: "health",
        openapi: { summary: "Health", description: "Named API health check." },
        handler: ->(_context) { { ok: true } }
      )

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
      peek = tools.fetch("Folder--peek").fetch("description")
      rename = tools.fetch("Folder--rename").fetch("description")
      lock = tools.fetch("Folder--lock").fetch("description")
      stats = tools.fetch("Folder--stats").fetch("description")
      health = tools.fetch("health").fetch("description")

      assert_includes peek, "Peek at this folder"
      peek_action_at = peek.index("Peek at this folder")
      peek_type_at = peek.index("A folder record in this workspace.")
      peek_access_at = peek.index("Access: View.")
      peek_tool_at = peek.index("Tool: capability_action")
      assert_includes peek, "Access: View."
      refute_includes peek, "Tool name:"
      refute_includes peek, "Runs on a "
      refute_includes peek, "Type: `Folder`"
      assert_operator peek_type_at, :>, peek_action_at
      assert_operator peek_access_at, :>, peek_type_at
      assert_operator peek_tool_at, :>, peek_access_at
      assert_includes rename, "Access: Edit."
      assert_includes lock, "Access: Admin."
      refute_includes stats, "Access:"
      refute_includes health, "Access:"
    end
  end

  def test_openapi_action_page_shows_host_overridden_access_role
    with_isolated_api_configuration do
      previous_roles = RecordingStudioApi.configuration.capability_action_roles.dup
      RecordingStudioApi.configuration.api :public
      register_tree_type(
        "Folder",
        operations: %i[index show],
        capability_actions: %i[peek]
      )
      register_capability_with_role(:peek, summary: "Peek at this folder", role: :view)
      RecordingStudioApi.configuration.capability_action_roles = { peek: :admin }

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      peek = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }.fetch("Folder--peek").fetch("description")

      assert_includes peek, "Access: Admin."
      refute_includes peek, "Access: View."
    ensure
      RecordingStudioApi.configuration.capability_action_roles = previous_roles
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
      attach = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "RecordingStudioPresskits::Files--attach" }
      page = attach.fetch("description")
      description_at = page.index("Signed blob from create_upload, or a list of attachments.")
      tool_at = page.index("Tool: capability_action")

      assert_equal "File - Attach", attach["title"]
      refute_includes page, "Attach a file"
      refute_includes page, "Tool name:"
      refute_includes page, "Runs on a "
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
      tag_names = spec.fetch("tags").map { |tag| tag["name"] }

      assert_equal [{ "name" => "Host", "tags" => %w[Core] }], spec["x-tagGroups"]
      assert_equal %w[Core], tag_names
    end
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

  def register_capability_with_role(name, summary:, role:, scope: :member)
    RecordingStudioApi.register_capability_action(
      name,
      capability: :accessible,
      handler: ->(_context) { { json: { ok: true } } },
      openapi: { summary: summary },
      required_role: role,
      scope: scope
    )
  end
end
