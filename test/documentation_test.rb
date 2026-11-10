# frozen_string_literal: true

require "test_helper"

class DocumentationTest < Minitest::Test
  include IsolatedApiConfiguration

  def test_page_lists_registered_types_tools_and_resource_template
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Folder", operations: %i[index show create update])
      register_tree_type("Page", operations: %i[index show create update])

      page = RecordingStudioMcp::Documentation.page(api: :public)

      assert_equal "public", page.api_key
      assert_equal "Public MCP", page.title
      refute_empty page.instructions
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
      register_tree_type("Folder", operations: %i[index show create update])
      register_tree_type("Page", operations: %i[index show create update])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      mcp = spec.fetch("x-mcp")
      names = mcp.fetch("tools").map { |tool| tool["name"] }
      schemas = spec.dig("components", "schemas")

      assert_equal "3.1.0", spec["openapi"]
      assert_equal "Public MCP", spec.dig("info", "title")
      refute_empty spec.dig("info", "description")
      assert_equal spec.dig("info", "description"), mcp["instructions"]
      assert_includes names, "list"
      assert_includes names, "describe"
      assert_includes schemas.keys, "Folder"
      assert_includes schemas.keys, "Page"
      assert_includes Array(schemas.dig("Folder", "x-mcp-operations")), "index"
      assert_equal "recording://{id}", mcp.dig("resources", 0, "uri")
      assert_equal "recording://{id}", mcp.dig("resourceTemplates", 0, "uriTemplate")
    end
  end
end
