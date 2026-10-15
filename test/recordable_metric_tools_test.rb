# frozen_string_literal: true

require "test_helper"

class RecordableMetricToolsTest < Minitest::Test
  def test_two_types_advertise_one_tool_per_metric
    with_metric_types do |surface|
      assert_equal(
        %w[list show create update capability_action describe folders-created_over_time folders-total pages-total],
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
      metric = surface.metric_tool("folders-total")

      assert_equal(
        {
          "filter" => { "name" => "Ada" },
          "q" => "Bea",
          "from" => "2026-04-01T00:00:00Z",
          "name" => "folders.total",
          "resource" => "folders"
        },
        RecordingStudioMcp::RecordableMetricTools.params_for(
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
      metric = surface.metric_tool("folders-total")

      assert_equal(
        {
          "q" => "",
          "filter" => { "name" => "" },
          "name" => "folders.total",
          "resource" => "folders"
        },
        RecordingStudioMcp::RecordableMetricTools.params_for(
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
        RecordingStudioMcp::RecordableMetricTools.params_for(metric, { "filter[name]" => "Ada" })
      end

      assert_equal "Send list filters as a filter object of attribute names", error.message
    end
  end

  def test_unknown_filter_attribute_and_non_string_values_are_rejected
    with_metric_types do |surface|
      metric = surface.metric_tool("folders-total")

      unknown = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::RecordableMetricTools.params_for(metric, { "filter" => { "missing" => "Ada" } })
      end
      assert_equal "Unknown filter attribute missing", unknown.message

      number = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::RecordableMetricTools.params_for(metric, { "q" => 1 })
      end
      assert_equal "q must be a string", number.message

      text = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        RecordingStudioMcp::RecordableMetricTools.params_for(metric, { "filter" => "Ada" })
      end
      assert_equal "filter must be an object", text.message
    end
  end

  def test_non_query_or_reserved_filter_parameter_fails_the_plan
    plan = RecordingStudioMcp::RecordableMetricTools::ArgumentPlan
    query = assert_raises(RecordingStudioApi::ConfigurationError) do
      plan.from([{ name: "from", in: "path", required: false, schema: { type: "string" } }])
    end
    assert_equal "Metric parameter from must be in query", query.message

    reserved = assert_raises(RecordingStudioApi::ConfigurationError) do
      plan.from([{ name: "filter", in: "query", required: false, schema: { type: "object" } }])
    end
    assert_equal "Metric parameter named filter is reserved for the filter object", reserved.message
  end

  def test_missing_definition_fails_the_surface
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api("Folder", metrics: %w[folders.absent])

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp::ToolSurface.for(api: "public")
      end
      assert_equal "Metric folders.absent is not registered with RecordingStudioMetrics", error.message
    end
  end

  def test_tool_name_longer_than_64_fails_the_surface
    leaf = "a" * 57
    identifier = "folders.#{leaf}"
    tool_name = "folders-#{leaf}"

    with_isolated_api_configuration do
      with_recordable_metric_registry do
        RecordingStudioApi.register_recordable_type_api(
          RecordableMetricToolHelpers::FOLDER,
          metrics: [identifier]
        )
        RecordingStudioMetrics.register(:folders, model: RecordableMetricToolHelpers::Folder, blast_radius: :root) do
          count leaf.to_sym, title: "Long"
        end

        error = assert_raises(RecordingStudioApi::ConfigurationError) do
          RecordingStudioMcp::ToolSurface.for(api: "public")
        end
        assert_equal 65, tool_name.length
        assert_includes error.message, tool_name
      end
    end
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
      properties: query_properties(filter_attribute: :name),
      required: [],
      additionalProperties: false
    }
  end

  def folders_created_over_time_schema
    properties = query_properties(filter_attribute: :name)
    properties[:interval] = properties[:interval].merge(enum: %w[day week])
    properties[:group_by] = properties[:group_by].merge(enum: %w[name])
    {
      type: "object",
      properties: properties,
      required: [],
      additionalProperties: false
    }
  end

  def pages_total_schema
    {
      type: "object",
      properties: query_properties(filter_attribute: :title),
      required: [],
      additionalProperties: false
    }
  end

  def query_properties(filter_attribute:)
    {
      from: {
        type: "string",
        format: "date-time",
        description: "Inclusive period start, as an ISO-8601 date-time. start and start_at are aliases."
      },
      to: {
        type: "string",
        format: "date-time",
        description: "Exclusive period end, as an ISO-8601 date-time. end and end_at are aliases."
      },
      interval: { type: "string", description: "Time-series bucket size." },
      group_by: { type: "string", description: "Grouping column for this metric." },
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
