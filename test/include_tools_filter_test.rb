# frozen_string_literal: true

require "test_helper"

class IncludeToolsFilterTest < Minitest::Test
  def test_restricted_server_docs_match_tools_list_and_omit_excluded_tools
    with_restricted_press_kit_server do
      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      listed = live_tool_names
      intro = spec.fetch("tags").find { |tag| tag["name"] == "PressKit" }.fetch("description")
      overview = spec.dig("info", "description").to_s
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("PressKit")
      documented = RecordingStudioMcp::Catalog.new(api: :public).documentation_type("PressKit")

      assert_equal listed.sort, docs_tool_names(spec).sort
      create_press_kit = RecordingStudioMcp.tool_name("PressKit", :create)
      assert_equal [create_press_kit, "describe", "read_skill"].sort, listed.sort
      refute_includes listed, "create"
      refute_includes listed, "list"
      refute_includes listed, "show"
      refute_includes listed, "capability_action"
      refute_includes listed, RecordingStudioMcp.tool_name("PressKit", :publish)
      refute_includes listed, "PressKit--publish"
      refute RecordingStudioMcp::Catalog.new(api: :public).capability_actions_advertised?
      spec.dig("x-mcp", "tools").each do |tool|
        refute tool["x-mcp-docs-only"], "#{tool['name']} must not be docs-only"
      end

      assert_equal [create_press_kit], described.fetch("tools")
      assert described.key?("parent")
      assert documented.key?("parent")
      refute described.key?("capability_actions")
      refute documented.key?("capability_actions")
      assert_includes intro, "Tool: #{create_press_kit}"
      refute_includes intro, "Tool: create with type `PressKit`"
      refute_includes intro, "Tool: list with type `PressKit`"
      refute_includes intro, "Tool: show with type `PressKit`"
      refute_includes intro, "capability_action"
      refute_includes intro, "Capability actions:"
      refute_includes intro, "publish"
      refute_includes overview, "Tool: create with type `PressKit`"
      refute_includes overview, "capability_action"
      refute_includes overview, "available actions"
      refute_includes listed_tool("describe")[:description], "available actions"
      refute describe_output_properties.key?(:capability_actions)
      refute describe_output_properties.key?("capability_actions")
    end
  end

  def test_full_server_still_lists_generic_tools_and_capability_actions
    with_isolated_api_configuration do
      register_named_capability(:publish)
      register_tree_type(
        "PressKit",
        operations: %i[index show create update],
        capability_actions: %i[publish]
      )
      RecordingStudioApi.register_resource_handler(
        "PressKit",
        :create,
        handler: ->(_context) { { json: { id: "kit-1", type: "PressKit" } } }
      )
      create_press_kit = RecordingStudioMcp.tool_name("PressKit", :create)
      RecordingStudioMcp.register_tool(
        name: create_press_kit,
        type: "PressKit",
        operation: :create,
        title: "Create press kit",
        description: "Create a press kit.",
        input: {},
        output: "the kit"
      )
      ensure_tree_server(:public, extra_tools: [create_press_kit])

      spec = RecordingStudioMcp::Documentation.openapi(api: :public)
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("PressKit")
      intro = spec.fetch("tags").find { |tag| tag["name"] == "PressKit" }.fetch("description")

      assert_equal live_tool_names.sort, docs_tool_names(spec).sort
      assert_includes described.fetch("tools"), "create"
      assert_includes described.fetch("tools"), "list"
      assert_includes described.fetch("tools"), "show"
      assert_includes described.fetch("tools"), "capability_action"
      assert_includes described.fetch("tools"), create_press_kit
      names = described.fetch("capability_actions").map { |action| action["name"] }

      assert_equal ["publish"], names
      assert_includes intro, "Tool: create with type `PressKit`"
      assert_includes intro, "Tool: capability_action with type `PressKit`."
      assert_includes intro, "Capability actions:"
      assert_includes intro, "- publish"
      @grant = role_grant(:admin)
      assert RecordingStudioMcp::Catalog.new(api: :public).capability_actions_advertised?
      assert describe_output_properties.key?(:capability_actions)
    end
  end

  def test_describe_keeps_nil_parent_and_omits_unadvertised_capability_actions
    with_restricted_press_kit_server do
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      catalog.stub(:parent_rules, nil) do
        described = catalog.describe("PressKit")
        documented = catalog.documentation_type("PressKit")

        assert described.key?("parent")
        assert_nil described.fetch("parent")
        refute described.key?("capability_actions")
        assert documented.key?("parent")
        assert_nil documented.fetch("parent")
        refute documented.key?("capability_actions")
      end
    end
  end

  def test_excluded_tools_are_unknown_and_do_not_run
    with_restricted_press_kit_server do
      before_creates = @creates
      before_publishes = @publishes

      %w[create list show capability_action].each do |name|
        result = call_tool(name, type: "PressKit", id: "kit-1", action: "publish", title: "Kit")

        assert_equal true, result[:isError], name
        assert_includes result.dig(:content, 0, :text), "Unknown tool #{name}"
      end

      unknown_publish = call_tool("PressKit--publish", type: "PressKit", id: "kit-1", action: "publish", title: "Kit")
      assert_equal true, unknown_publish[:isError]
      assert_includes unknown_publish.dig(:content, 0, :text), "Unknown tool PressKit--publish"

      created = call_tool(RecordingStudioMcp.tool_name("PressKit", :create), title: "Kit")

      refute created[:isError], created.dig(:content, 0, :text)
      assert_equal "kit-1", created.dig(:structuredContent, "id")
      assert_equal before_creates + 1, @creates
      assert_equal before_publishes, @publishes
    end
  end

  private

  def with_restricted_press_kit_server
    with_isolated_api_configuration do
      @creates = 0
      @publishes = 0
      RecordingStudioApi.register_capability_action(
        :publish,
        capability: :accessible,
        handler: lambda { |_context|
          @publishes += 1
          { json: { ok: true } }
        },
        openapi: { summary: "Publish" }
      )
      register_tree_type(
        "PressKit",
        operations: %i[index show create update],
        capability_actions: %i[publish]
      )
      RecordingStudioApi.register_resource_handler(
        "PressKit",
        :create,
        handler: lambda { |_context|
          @creates += 1
          { json: { id: "kit-1", type: "PressKit" } }
        }
      )
      create_press_kit = RecordingStudioMcp.tool_name("PressKit", :create)
      publish_press_kit = RecordingStudioMcp.tool_name("PressKit", :publish)
      RecordingStudioMcp.register_tool(
        name: create_press_kit,
        type: "PressKit",
        operation: :create,
        title: "Create press kit",
        description: "Create a press kit.",
        input: {},
        output: "the kit"
      )
      RecordingStudioMcp.register_tool(
        name: publish_press_kit,
        type: "PressKit",
        action: :publish,
        title: "Publish press kit",
        description: "Publish a press kit.",
        input: {},
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) do
        include_tools create_press_kit
      end
      @grant = role_grant(:admin)
      yield
    end
  end

  def register_named_capability(name)
    return if RecordingStudioApi.capability_action(name, api: :public)

    RecordingStudioApi.register_capability_action(
      name,
      capability: :accessible,
      handler: ->(_context) { { json: { ok: true } } },
      openapi: { summary: name.to_s.humanize }
    )
  end

  def live_tool_names
    RecordingStudioMcp::Tools.definitions(api: :public).map { |tool| tool[:name].to_s }
  end

  def docs_tool_names(spec)
    spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
  end

  def describe_output_properties
    listed_tool("describe").fetch(:outputSchema).fetch(:properties)
  end

  def listed_tool(name)
    RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
      access_grant: @grant
    ).body.dig(:result, :tools).find { |tool| tool[:name] == name }
  end

  def call_tool(name, **arguments)
    RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => { "name" => name, "arguments" => arguments.stringify_keys }
      },
      access_grant: @grant
    ).body.fetch(:result)
  end
end
