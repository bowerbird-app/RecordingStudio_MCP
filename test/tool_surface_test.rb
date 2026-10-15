# frozen_string_literal: true

require "test_helper"

class ToolSurfaceTest < Minitest::Test
  include RecordableMetricToolHelpers

  def test_tree_only_surface
    with_isolated_api_configuration do
      register_tree_type("Page")
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal true, surface.tree_enabled?
      assert_equal false, surface.endpoints_enabled?
      assert_equal true, surface.known?("describe")
      assert_equal true, surface.tree_tool?("list")
      assert_equal false, surface.known?("ping")
      assert_equal %w[list show create update capability_action describe], surface.tool_names
      assert_equal false, surface.known?("delete")
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

  def test_no_recordable_metrics_adds_no_tools
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal false, surface.metric_tools?
      assert_equal %w[list show create update capability_action describe ping], surface.tool_names
    end
  end

  def test_recordable_metric_tool_is_read_only_and_sits_between_families
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_folder_and_page_metrics
        RecordingStudioApi.register_endpoint(
          :zeta,
          http_verb: :get,
          path: "zeta",
          handler: ->(_context) { { ok: true } }
        )
        RecordingStudioApi.register_endpoint(
          :alpha,
          http_verb: :post,
          path: "alpha",
          handler: ->(_context) { { ok: true } }
        )
        surface = RecordingStudioMcp::ToolSurface.for(api: "public")

        assert_equal(
          %w[list show create update capability_action describe] +
            %w[folders-created_over_time folders-total pages-total] +
            %w[alpha zeta],
          surface.tool_names
        )
        assert_equal true, surface.known?("folders-total")
        assert_equal false, surface.tree_tool?("folders-total")
        assert_equal true, surface.read_only_tool?("folders-total")
        error = assert_raises(ArgumentError) { surface.endpoint_for("folders-total") }
        assert_includes error.message, "folders-total"
      end
    end
  end

  def test_metric_tool_name_collision_raises
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.register_recordable_type_api(
          RecordableMetricToolHelpers::FOLDER,
          writable_attributes: %i[name],
          operations: %i[index show create update],
          metrics: %w[folders.total]
        )
        register_folder_metric_definitions
        RecordingStudioApi.register_endpoint(
          "folders-total",
          http_verb: :get,
          path: "folders-total",
          handler: ->(_context) { { ok: true } }
        )

        error = assert_raises(RecordingStudioApi::ConfigurationError) do
          RecordingStudioMcp::ToolSurface.for(api: "public")
        end
        assert_includes error.message, "folders-total"
        assert_includes error.message, "collide"
      end
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
