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

  def test_page_uses_oauth_client_named_api
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
      client = Struct.new(:api_key).new("operations")

      page = RecordingStudioMcp::Documentation.page(api: :public, oauth_client: client)

      assert_equal "operations", page.api_key
      names = page.tools.map { |tool| tool[:name] || tool["name"] }
      assert_includes names, "ops_ping"
      refute_includes page.types.map { |entry| entry["type"] }, "Folder"
    end
  end

  def test_page_is_nil_safe_when_describe_raises
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Folder")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      catalog.stub(:describe, ->(*) { raise "gone" }) do
        RecordingStudioMcp::Catalog.stub(:new, catalog) do
          page = RecordingStudioMcp::Documentation.page(api: :public)
          folder = page.types.find { |entry| entry["type"] == "Folder" }

          assert_equal [], folder["operations"]
          assert_equal [], folder["writable_fields"]
        end
      end
    end
  end

  def test_page_is_nil_safe_for_blank_oauth_client
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      page = RecordingStudioMcp::Documentation.page(api: :public, oauth_client: nil)

      assert_equal "public", page.api_key
      assert_equal [], page.types
      assert_equal "recording://{id}", page.resource_template[:uriTemplate]
    end
  end

  def test_unknown_api_raises
    with_isolated_api_configuration do
      error = assert_raises(ArgumentError) { RecordingStudioMcp::Documentation.page(api: :missing) }
      assert_includes error.message, "unknown API"
    end
  end
end
