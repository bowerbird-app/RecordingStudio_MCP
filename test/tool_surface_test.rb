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
      assert_equal %w[list show create update describe ping], surface.tool_names
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
          %w[list show create update describe] +
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

  def test_metric_tool_name_collision_is_skipped
    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)
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
        surface = RecordingStudioMcp::ToolSurface.for(api: "public")

        assert_includes surface.tool_names, "folders-total"
        assert_equal 1, surface.tool_names.count("folders-total")
        assert_nil surface.metric_tool("folders-total")
        assert_equal :get, surface.endpoint_for("folders-total").http_verb
        assert_includes surface.tool_names, "list"
      end
    end
    assert_includes warnings.string, "folders-total"
    assert_includes warnings.string, "endpoint tool"
  ensure
    Rails.logger = previous if previous
  end

  def test_bad_endpoint_names_are_skipped
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index])
      RecordingStudioApi.register_endpoint(
        :list,
        http_verb: :get,
        path: "custom-list",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        "bad name",
        http_verb: :get,
        path: "bad-name",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        "1bad",
        http_verb: :get,
        path: "one-bad",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[list describe ping], surface.tool_names
      assert_equal true, surface.known?("list")
      assert_equal true, surface.tree_tool?("list")
      assert_equal false, surface.known?("bad name")
      assert_equal false, surface.known?("1bad")
      RecordingStudioApi.register_endpoint(
        "presskits.edit",
        http_verb: :patch,
        path: "presskits/:id",
        handler: ->(_context) { { ok: true } }
      )
      dotted = RecordingStudioMcp::ToolSurface.for(api: "public")
      assert_equal true, dotted.known?("presskits.edit")
    end
  end

  def test_show_only_omits_list
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show])
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[show describe], surface.tool_names
      assert_equal false, surface.known?("list")
    end
  end

  def test_index_only_omits_show
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index])
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_equal %w[list describe], surface.tool_names
      assert_equal false, surface.known?("show")
    end
  end

  def test_empty_operations_advertise_every_tree_tool
    with_isolated_api_configuration do
      register_tree_type("Page", operations: [])
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_includes surface.tool_names, "delete"
      assert_includes surface.tool_names, "create"
    end
  end

  def test_nil_operations_follow_named_api_default_access
    with_isolated_api_configuration do
      register_tree_type("Article", operations: nil)
      public_surface = RecordingStudioMcp::ToolSurface.for(api: "public")

      assert_includes public_surface.tool_names, "delete"
    end

    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:docs)
      register_tree_type("Article", api: :docs, operations: nil)
      read_only = RecordingStudioMcp::ToolSurface.for(api: "docs")

      assert_equal %w[list show describe], read_only.tool_names
    end

    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:docs).default_access = :read_write
      register_tree_type("Note", api: :docs, operations: nil)
      writable = RecordingStudioMcp::ToolSurface.for(api: "docs")

      assert_includes writable.tool_names, "delete"
    end
  end

  def test_view_grant_hides_edit_tools_and_deleted_grant_hides_reads
    with_isolated_api_configuration do
      register_ping_capability(required_role: :view)
      RecordingStudioApi.register_capability_action(
        :shout,
        capability: :accessible,
        required_role: :edit,
        handler: ->(_context) { { json: { ok: true } } }
      )
      register_tree_type(
        "Page",
        operations: %i[index show create update destroy],
        capability_actions: %i[ping shout]
      )

      view = RecordingStudioMcp::ToolSurface.for(access_grant: role_grant(:view))
      admin = RecordingStudioMcp::ToolSurface.for(access_grant: role_grant(:admin))
      deleted = RecordingStudioMcp::ToolSurface.for(access_grant: role_grant(nil))

      assert_equal %w[list show capability_action describe], view.tool_names
      assert_equal %w[list show create update delete capability_action describe], admin.tool_names
      assert_equal %w[describe], deleted.tool_names
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
