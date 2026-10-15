# frozen_string_literal: true

require "test_helper"

class CatalogMetricToolsTest < Minitest::Test
  include RecordableMetricToolHelpers

  def test_discovery_lists_one_tool_per_exposed_metric
    with_widget_metrics do
      surface = RecordingStudioMcp::ToolSurface.for(api: "public")
      total = tool(surface, "widgets-total")
      series = tool(surface, "widgets-created_over_time")

      assert_equal %w[widgets-created_over_time widgets-total], surface.tool_names
      assert_equal true, surface.catalog_metric_tools?
      assert_equal false, surface.recordable_metric_tools?
      assert_equal true, surface.read_only_tool?("widgets-total")
      assert_equal "Widgets", total.fetch(:title)
      assert_equal "How many widgets.", total.fetch(:description)
      assert_equal false, total.dig(:inputSchema, :additionalProperties)
      assert_equal false, total.dig(:inputSchema, :properties, :filters, :additionalProperties)
      assert_equal %w[closed open], total.dig(:inputSchema, :properties, :filters, :properties, :status, :enum).sort
      refute total.dig(:inputSchema, :properties).key?(:from)
      assert_equal "Same as start.", series.dig(:inputSchema, :properties, :start, :description)
      assert_equal "Same as start.", series.dig(:inputSchema, :properties, :start_at, :description)
      assert_equal "Same as end.", series.dig(:inputSchema, :properties, :end, :description)
      assert_equal "Same as end.", series.dig(:inputSchema, :properties, :end_at, :description)
      assert_equal %w[day week], series.dig(:inputSchema, :properties, :interval, :enum)
      assert_equal ["status"], series.dig(:inputSchema, :properties, :group_by, :enum)
      assert_equal false, series.dig(:inputSchema, :additionalProperties)
      assert_includes RecordingStudioMcp::Instructions.text, "same as from"
      refute_includes RecordingStudioMcp::Instructions.text, "filter object of attribute names"
    end
  end

  def test_execute_returns_the_handler_error_for_a_bad_window_and_unknown_argument
    with_widget_metrics do
      grant = catalog_grant(allowed: true)
      unknown = RecordingStudioMcp::Dispatcher.call(
        tool_name: "widgets-created_over_time",
        arguments: { "nope" => "1" },
        access_grant: grant
      )
      window = RecordingStudioMcp::Dispatcher.call(
        tool_name: "widgets-created_over_time",
        arguments: { "from" => "2026-04-01T00:00:00Z", "start" => "2026-04-02T00:00:00Z" },
        access_grant: grant
      )

      assert_equal true, unknown[:isError]
      assert_equal "Unknown argument nope", unknown.dig(:content, 0, :text)
      assert_equal true, window[:isError]
      assert_equal "start and from must match when both are provided", window.dig(:content, 0, :text)
    end
  end

  def test_listed_metric_authorization_error_is_a_tool_error
    authorize = lambda do |context|
      params = context.params
      metric_name = params[:name] || params["name"]
      raise RecordingStudioApi::AuthorizationError, "Not authorized to run this metric" if metric_name.present?

      true
    end
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_widgets(authorize)
        grant = catalog_grant(allowed: true)
        assert_includes RecordingStudioMcp::ToolSurface.for(access_grant: grant).tool_names, "widgets-total"

        result = RecordingStudioMcp::Protocol.handle(
          {
            "jsonrpc" => "2.0",
            "id" => 8,
            "method" => "tools/call",
            "params" => { "name" => "widgets-total", "arguments" => {} }
          },
          access_grant: grant
        )

        assert_nil result.body[:error]
        assert_equal true, result.body.dig(:result, :isError)
        assert_equal "Not authorized to run this metric", result.body.dig(:result, :content, 0, :text)
      end
    end
  end

  def test_string_filters_are_a_tool_error
    with_widget_metrics do
      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "widgets-total",
        arguments: { "filters" => "open" },
        access_grant: catalog_grant(allowed: true)
      )

      assert_equal true, result[:isError]
      assert_equal "filters must be an object", result.dig(:content, 0, :text)
    end
  end

  def test_non_object_arguments_are_invalid_params
    with_widget_metrics do
      result = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "tools/call",
          "params" => { "name" => "widgets-total", "arguments" => [1] }
        },
        access_grant: catalog_grant(allowed: true)
      )

      assert_equal RecordingStudioMcp::Protocol::INVALID_PARAMS, result.body.dig(:error, :code)
    end
  end

  def test_authorize_hook_hides_the_tool_and_execute_is_denied
    with_widget_metrics do
      hidden = RecordingStudioMcp::ToolSurface.for(access_grant: catalog_grant(allowed: false))
      shown = RecordingStudioMcp::ToolSurface.for(access_grant: catalog_grant(allowed: true))
      denied = RecordingStudioMcp::Dispatcher.call(
        tool_name: "widgets-total",
        arguments: {},
        access_grant: catalog_grant(allowed: false)
      )
      tool = RecordingStudioMcp::CatalogMetricTools.collect(
        RecordingStudioMcp::Catalog.new(api: "public"),
        nil
      ).find { |candidate| candidate.name.to_s == "widgets-total" }
      error = assert_raises(RecordingStudioApi::AuthorizationError) do
        RecordingStudioMcp::CatalogMetricTools.execute(tool, {}, catalog_grant(allowed: false))
      end

      refute_includes hidden.tool_names, "widgets-total"
      assert_includes shown.tool_names, "widgets-total"
      assert_equal true, denied[:isError]
      assert_includes denied.dig(:content, 0, :text), "Unknown tool widgets-total"
      assert_equal "Not authorized to run this metric", error.message
    end
  end

  def test_catalog_tools_skip_the_recordable_view_gate
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_folder_and_page_metrics
        register_widgets(->(_context) { true })
        surface = RecordingStudioMcp::ToolSurface.for(access_grant: catalog_grant(allowed: false))

        refute_includes surface.tool_names, "folders-total"
        assert_includes surface.tool_names, "widgets-total"
      end
    end
  end

  def test_resource_allowlist_limits_catalog_tools
    with_widget_metrics do
      with_isolated_mcp_configuration do
        RecordingStudioMcp.configuration.catalog_metric_resources = ["other"]
        hidden = RecordingStudioMcp::ToolSurface.for(api: "public").tool_names

        RecordingStudioMcp.configuration.catalog_metric_resources = ["widgets"]
        shown = RecordingStudioMcp::ToolSurface.for(api: "public").tool_names

        RecordingStudioMcp.configuration.catalog_metric_resources = []
        empty = RecordingStudioMcp::ToolSurface.for(api: "public").tool_names

        refute_includes hidden, "widgets-total"
        assert_includes shown, "widgets-total"
        refute_includes empty, "widgets-total"
      end
    end
  end

  def test_bad_metric_name_is_skipped
    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)
    leaf = "a" * 60
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioMetrics.register(:widgets, model: RecordableMetricToolHelpers::Folder, blast_radius: :root) do
          count :total, title: "Widgets", expose: { api: [:public] }
          count leaf.to_sym, title: "Long", expose: { api: [:public] }
        end
        names = RecordingStudioMcp::ToolSurface.for(api: "public").tool_names

        assert_includes names, "widgets-total"
        refute_includes names, "widgets-#{leaf}"
      end
    end
    assert_includes warnings.string, "WARN --"
    assert_includes warnings.string, "widgets.#{leaf}"
  ensure
    Rails.logger = previous if previous
  end

  def test_catalog_metric_name_collision_is_skipped
    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_widgets(->(_context) { true })
        RecordingStudioApi.register_endpoint(
          "widgets-total",
          http_verb: :get,
          path: "widgets-total",
          handler: ->(_context) { { ok: true } }
        )
        surface = RecordingStudioMcp::ToolSurface.for(api: "public")

        assert_equal 1, surface.tool_names.count("widgets-total")
        assert_nil surface.metric_tool("widgets-total")
        assert_equal :get, surface.endpoint_for("widgets-total").http_verb
        assert_includes surface.tool_names, "widgets-created_over_time"
      end
    end
    assert_includes warnings.string, "WARN --"
    assert_includes warnings.string, "widgets-total"
  ensure
    Rails.logger = previous if previous
  end

  private

  def with_widget_metrics
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_widgets(->(context) { context.access_grant.allowed })
        yield
      end
    end
  end

  def register_widgets(authorize)
    RecordingStudioMetrics.register(
      :widgets,
      model: RecordableMetricToolHelpers::Folder,
      blast_radius: :site,
      api_authorize: authorize
    ) do
      count :total, title: "Widgets", description: "How many widgets.", expose: { api: [:public] } do
        filter :status, type: :enum, field: :status, options: %w[open closed], label: "Status"
      end
      timeseries :created_over_time,
                 title: "Widgets over time",
                 field: :created_at,
                 intervals: %i[day week],
                 group_by: %i[status],
                 expose: { api: [:public] }
    end
  end

  def catalog_grant(allowed:)
    client = Struct.new(:api_key).new("public")
    recording = Object.new
    Struct.new(
      :api_client, :credential, :access_recording, :root_recording, :scope_recording, :allowed,
      keyword_init: true
    ) do
      def authorized?(**)
        allowed
      end

      def actor
        nil
      end

      def accessible_recordings(**)
        []
      end
    end.new(
      api_client: client,
      credential: nil,
      access_recording: nil,
      root_recording: recording,
      scope_recording: recording,
      allowed: allowed
    )
  end

  def tool(surface, name)
    surface.tool_definitions.find { |entry| entry.fetch(:name) == name }
  end
end
