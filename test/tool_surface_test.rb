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
      assert_equal RecordingStudioMcp::Tools::TREE_NAMES, surface.tool_names
      assert_equal true, surface.read_only_tool?("list")
      assert_equal false, surface.read_only_tool?("create")
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
