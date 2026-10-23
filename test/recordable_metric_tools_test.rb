# frozen_string_literal: true

require "test_helper"

class RecordableMetricToolsTest < Minitest::Test
  include RecordableMetricToolHelpers

  def test_two_types_advertise_one_tool_per_metric
    with_metric_types do |surface|
      assert_equal(
        %w[list show create update describe folders-created_over_time folders-total pages-total],
        surface.tool_names
      )

      total = tool(surface, "folders-total")
      created = tool(surface, "folders-created_over_time")
      pages = tool(surface, "pages-total")

      assert_equal "Folders total", total.fetch(:title)
      assert_equal "How many folders are in this scope.", total.fetch(:description)
      assert_equal folders_total_schema, total.fetch(:inputSchema)
      assert_equal read_only_annotations, total.fetch(:annotations)
      refute total.key?(:_meta)

      assert_equal "Folders created over time", created.fetch(:title)
      assert_equal "Folders created in the window.", created.fetch(:description)
      assert_equal folders_created_over_time_schema, created.fetch(:inputSchema)
      assert_equal read_only_annotations, created.fetch(:annotations)

      assert_equal "Pages total", pages.fetch(:title)
      assert_equal "How many pages are in this scope.", pages.fetch(:description)
      assert_equal pages_total_schema, pages.fetch(:inputSchema)
      assert_equal read_only_annotations, pages.fetch(:annotations)
    end
  end

  def test_filter_object_becomes_nested_filter_param
    with_metric_types do |surface|
      metric = surface.metric_tool("folders-created_over_time")

      assert_equal(
        {
          "filter" => { "name" => "Ada" },
          "q" => "Bea",
          "from" => "2026-04-01T00:00:00Z",
          "name" => "folders.created_over_time",
          "resource" => "folders"
        },
        RecordingStudioMcp::MetricTools.params_for(
          metric,
          {
            "filter" => { "name" => "Ada" },
            "q" => "Bea",
            "from" => "2026-04-01T00:00:00Z",
            "to" => nil
          }
        )
      )
    end
  end

  def test_nil_arguments_are_dropped_and_empty_strings_stay
    with_metric_types do |surface|
      metric = surface.metric_tool("folders-created_over_time")

      assert_equal(
        {
          "q" => "",
          "filter" => { "name" => "" },
          "name" => "folders.created_over_time",
          "resource" => "folders"
        },
        RecordingStudioMcp::MetricTools.params_for(
          metric,
          { "q" => "", "from" => nil, "filter" => { "name" => "" } }
        )
      )
    end
  end

  def test_bracket_filter_key_is_rejected
    with_metric_types do |surface|
      metric = surface.metric_tool("folders-total")
      error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::MetricTools.params_for(metric, { "filter[name]" => "Ada" })
      end

      assert_equal "Send list filters as a filter object of attribute names", error.message
    end
  end

  def test_filter_keeps_a_non_string_name_and_rejects_a_non_string_q
    with_metric_types do |surface|
      metric = surface.metric_tool("folders-total")

      passed = RecordingStudioMcp::MetricTools.params_for(
        metric, { "filter" => { "missing" => "Ada", "name" => 1 } }
      )
      assert_equal({ "missing" => "Ada", "name" => 1 }, passed.fetch("filter"))

      number = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::MetricTools.params_for(metric, { "q" => 1 })
      end
      assert_equal "q must be a string", number.message

      text = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::MetricTools.params_for(metric, { "filter" => "Ada" })
      end
      assert_equal "filter must be an object", text.message
    end
  end

  def test_period_aliases_pass_through_to_show
    with_metric_types do |surface|
      metric = surface.metric_tool("folders-created_over_time")

      assert_equal(
        {
          "start" => "2026-04-01T00:00:00Z",
          "start_at" => "2026-04-02T00:00:00Z",
          "end" => "2026-05-01T00:00:00Z",
          "end_at" => "2026-05-02T00:00:00Z",
          "name" => "folders.created_over_time",
          "resource" => "folders"
        },
        RecordingStudioMcp::MetricTools.params_for(
          metric,
          {
            "start" => "2026-04-01T00:00:00Z",
            "start_at" => "2026-04-02T00:00:00Z",
            "end" => "2026-05-01T00:00:00Z",
            "end_at" => "2026-05-02T00:00:00Z"
          }
        )
      )
    end
  end

  def test_count_metric_schema_copies_the_api_catalog
    with_metric_types do |surface|
      total = tool(surface, "folders-total").fetch(:inputSchema).fetch(:properties)
      refute total.key?(:from)
      refute total.key?(:interval)
      refute total.key?(:group_by)
      assert_equal "string", total.dig(:q, :type)
      window = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::MetricTools.params_for(
          surface.metric_tool("folders-total"),
          { "from" => "2026-04-01T00:00:00Z" }
        )
      end
      assert_equal "Unknown argument from", window.message

      created_entry = RecordingStudioApi.metrics_for(RecordableMetricToolHelpers::FOLDER, api: "public")
                                        .find { |candidate| candidate.name == "folders.created_over_time" }
      interval = created_entry.parameters.find { |parameter| parameter.fetch(:name) == "interval" }
      group_by = created_entry.parameters.find { |parameter| parameter.fetch(:name) == "group_by" }
      created = tool(surface, "folders-created_over_time").fetch(:inputSchema).fetch(:properties)

      assert_equal %w[day week], interval.dig(:schema, :enum)
      assert_equal %w[day week], created.dig(:interval, :enum)
      assert_equal ["name"], group_by.dig(:schema, :enum)
      assert_equal ["name"], created.dig(:group_by, :enum)
      assert_includes created.dig(:from, :description), "start must match from"
    end
  end

  def test_metrics_stay_hidden_when_index_is_off
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.register_recordable_type_api(
          RecordableMetricToolHelpers::FOLDER,
          operations: %i[show],
          metrics: %w[folders.total],
          writable_attributes: %i[name]
        )
        register_folder_metric_definitions
        names = RecordingStudioMcp::ToolSurface.for(api: "public").tool_names

        assert_includes names, "show"
        refute_includes names, "folders-total"
      end
    end
  end

  def test_metric_tools_follow_view_access
    with_metric_types do
      hidden = RecordingStudioMcp::ToolSurface.for(access_grant: view_grant(allowed: false))
      shown = RecordingStudioMcp::ToolSurface.for(access_grant: view_grant(allowed: true))

      refute_includes hidden.tool_names, "folders-total"
      refute_includes hidden.tool_names, "pages-total"
      assert_includes shown.tool_names, "folders-total"
      assert_includes shown.tool_names, "pages-total"
    end
  end

  def test_dispatcher_rejects_non_object_metric_arguments
    with_metric_types do
      grant = view_grant(allowed: true)
      ["nope", [1]].each do |arguments|
        result = RecordingStudioMcp::Dispatcher.call(
          tool_name: "folders-total",
          arguments: arguments,
          access_grant: grant
        )

        assert_equal true, result[:isError]
        assert_equal "arguments must be an object", result.dig(:content, 0, :text)
      end
    end
  end

  def test_non_query_or_reserved_filter_parameter_fails_the_plan
    plan = RecordingStudioMcp::MetricTools::ArgumentPlan
    query = assert_raises(RecordingStudioApi::ConfigurationError) do
      plan.from([{ name: "from", in: "path", required: false, schema: { type: "string" } }])
    end
    assert_equal "Metric parameter from must be in query", query.message

    reserved = assert_raises(RecordingStudioApi::ConfigurationError) do
      plan.from([{ name: "filter", in: "query", required: false, schema: { type: "object" } }])
    end
    assert_equal "Metric parameter named filter is reserved for the filter object", reserved.message
  end

  def test_unregistered_metric_is_skipped_and_registered_sibling_keeps_its_schema
    solo = nil
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.register_recordable_type_api(
          RecordableMetricToolHelpers::FOLDER,
          writable_attributes: %i[name],
          operations: %i[index],
          metrics: %w[folders.total]
        )
        register_folder_metric_definitions
        solo = tool(RecordingStudioMcp::ToolSurface.for(api: "public"), "folders-total").fetch(:inputSchema)
      end
    end

    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.register_recordable_type_api(
          RecordableMetricToolHelpers::FOLDER,
          writable_attributes: %i[name],
          operations: %i[index],
          metrics: %w[folders.absent folders.total]
        )
        register_folder_metric_definitions
        surface = RecordingStudioMcp::ToolSurface.for(api: "public")

        assert_includes surface.tool_names, "folders-total"
        assert_includes surface.tool_names, "list"
        refute_includes surface.tool_names, "folders-absent"
        assert_equal solo, tool(surface, "folders-total").fetch(:inputSchema)
      end
    end
    assert_includes warnings.string, "WARN --"
    assert_includes warnings.string, "folders.absent"
    assert_includes warnings.string, "is not registered with RecordingStudioMetrics"
  ensure
    Rails.logger = previous if previous
  end

  def test_invalid_tool_name_is_skipped_and_other_metrics_stay
    leaf = "a" * 57
    identifier = "folders.#{leaf}"
    tool_name = "folders-#{leaf}"
    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)

    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.register_recordable_type_api(
          RecordableMetricToolHelpers::FOLDER,
          metrics: [identifier, "folders.total"],
          writable_attributes: %i[name],
          operations: %i[index show]
        )
        RecordingStudioMetrics.register(:folders, model: RecordableMetricToolHelpers::Folder, blast_radius: :root) do
          count leaf.to_sym, title: "Long"
          count :total, title: "Folders", description: "How many folders are in this scope."
        end

        names = RecordingStudioMcp::ToolSurface.for(api: "public").tool_names
        assert_equal 65, tool_name.length
        refute_includes names, tool_name
        assert_includes names, "folders-total"
        assert_includes names, "list"
        assert_includes warnings.string, tool_name
      end
    end
  ensure
    Rails.logger = previous
  end

  private

  def with_metric_types
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_folder_and_page_metrics
        yield RecordingStudioMcp::ToolSurface.for(api: "public")
      end
    end
  end

  def tool(surface, name)
    surface.tool_definitions.find { |entry| entry.fetch(:name) == name }
  end

  def read_only_annotations
    { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  end

  def folders_total_schema
    {
      type: "object",
      properties: filter_properties(filter_attribute: :name),
      required: [],
      additionalProperties: false
    }
  end

  def folders_created_over_time_schema
    {
      type: "object",
      properties: window_properties.merge(filter_properties(filter_attribute: :name)),
      required: [],
      additionalProperties: false
    }
  end

  def pages_total_schema
    {
      type: "object",
      properties: filter_properties(filter_attribute: :title),
      required: [],
      additionalProperties: false
    }
  end

  def view_grant(allowed:)
    client = Struct.new(:api_key).new("public")
    recording = Object.new
    fields = %i[api_client allowed scope_recording root_recording credential access_recording accessible_recordings]
    Struct.new(*fields, keyword_init: true) do
      def authorized?(**)
        allowed
      end
    end.new(
      api_client: client, allowed: allowed, scope_recording: recording, root_recording: recording,
      credential: nil, access_recording: nil, accessible_recordings: []
    )
  end

  def window_properties
    {
      from: {
        type: "string",
        format: "date-time",
        description: "Inclusive period start, as an ISO-8601 date-time. start must match from when both are sent. " \
                     "start_at is the fallback."
      },
      start: { type: "string", format: "date-time", description: "Same as start." },
      start_at: { type: "string", format: "date-time", description: "Same as start." },
      to: {
        type: "string",
        format: "date-time",
        description: "Exclusive period end, as an ISO-8601 date-time. end must match to when both are sent. " \
                     "end_at is the fallback."
      },
      end: { type: "string", format: "date-time", description: "Same as end." },
      end_at: { type: "string", format: "date-time", description: "Same as end." },
      interval: { type: "string", description: "Time-series bucket size.", enum: %w[day week] },
      group_by: {
        type: "string",
        description: "Grouping column for this metric. Do not allowlist a column that holds personal data. " \
                     "Groups under min_group_size fold into other.",
        enum: %w[name]
      }
    }
  end

  def filter_properties(filter_attribute:)
    {
      q: {
        type: "string",
        description: "Case-insensitive substring search across filterable attributes for this resource."
      },
      filter: {
        type: "object",
        additionalProperties: false,
        description: "Exact-match list filters. Keys are attribute names. The API reads this as params[:filter].",
        properties: {
          filter_attribute => {
            type: "string",
            description: "Exact match filter on #{filter_attribute}."
          }
        }
      }
    }
  end
end
