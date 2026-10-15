# frozen_string_literal: true

require "test_helper"

class ToolSurfaceTest < Minitest::Test
  def test_tree_only_surface
    with_isolated_api_configuration do
      register_tree_type("Page")
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal true, surface.tree_enabled?
      assert_equal false, surface.endpoints_enabled?
      assert_equal true, surface.known?("describe")
      assert_equal true, surface.tree_tool?("list")
      assert_equal false, surface.known?("ping")
      assert_equal %w[list show create update describe], surface.tool_names
      assert_equal false, surface.known?("capability_action")
      assert_equal false, surface.known?("delete")
      assert_equal true, surface.read_only_tool?("list")
      assert_equal false, surface.read_only_tool?("create")
    end
  end

  def test_read_only_surface_omits_write_tools
    with_isolated_api_configuration do
      register_tree_type("SupportPage", operations: %i[index show])
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[list show describe], surface.tool_names
      assert_equal true, surface.known?("list")
      assert_equal true, surface.known?("show")
      assert_equal true, surface.known?("describe")
      assert_equal false, surface.known?("create")
      assert_equal false, surface.known?("update")
      assert_equal false, surface.known?("capability_action")
      assert_equal false, surface.known?("delete")
      assert_equal true, surface.read_only_tool?("list")
      assert_equal true, surface.read_only_tool?("describe")
    end
  end

  def test_editable_surface_includes_create_and_update
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index show create update])
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[list show create update describe], surface.tool_names
      assert_equal true, surface.known?("create")
      assert_equal true, surface.known?("update")
      assert_equal false, surface.known?("capability_action")
      assert_equal false, surface.read_only_tool?("create")
    end
  end

  def test_union_across_types_advertises_create_when_any_type_allows_it
    with_isolated_api_configuration do
      register_tree_type("SupportPage", operations: %i[index show])
      register_tree_type("Page", operations: %i[index show create update])
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[list show create update describe], surface.tool_names
    end
  end

  def test_full_surface_with_destroy_and_capability_actions
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type(
        "Page",
        operations: %i[index show create update destroy],
        capability_actions: %i[ping]
      )
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[list show create update delete capability_action describe], surface.tool_names
    end
  end

  def test_catalog_only_surface
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :shout,
        http_verb: :post,
        path: "shout",
        handler: ->(_context) { { ok: true } }
      )
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal false, surface.tree_enabled?
      assert_equal true, surface.endpoints_enabled?
      assert_equal false, surface.tree_tool?("list")
      assert_equal true, surface.known?("ping")
      assert_equal %w[ping shout], surface.tool_names
      assert_equal :get, surface.endpoint_for("ping").http_verb
      assert_equal true, surface.read_only_tool?("ping")
      assert_equal false, surface.read_only_tool?("shout")
    end
  end

  def test_endpoint_name_collision_raises
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :list,
        http_verb: :get,
        path: "custom-list",
        handler: ->(_context) { { ok: true } }
      )

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp::ToolSurface.for(api: "public")
      end
      assert_includes error.message, "list"
      assert_includes error.message, "collide"
    end
  end

  def test_unknown_endpoint_for_raises
    with_isolated_api_configuration do
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      error = assert_raises(ArgumentError) { surface.endpoint_for("missing") }
      assert_includes error.message, "missing"
    end
  end
end
