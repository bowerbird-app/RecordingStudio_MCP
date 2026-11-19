# frozen_string_literal: true

require "test_helper"
require_relative "support/mcp_test_kits"

class NamedPressKitProtocolTest < Minitest::Test
  PRESS_KIT = "McpTestKits::Kit"

  FakeRecording = Struct.new(:id, :recordable_type)
  FakeRelation = Struct.new(:recording) do
    def find_by(id:)
      recording if recording&.id.to_s == id.to_s
    end
  end

  def test_tools_call_resolves_a_namespaced_type_through_the_public_name_catalog
    with_press_kit_surface do
      result = call_tool("create", type: "PressKit", parent_id: "center-1", title: "Kit")
      rejected = call_tool("create", type: PRESS_KIT, parent_id: "center-1", title: "Kit")

      refute result[:isError], result.dig(:content, 0, :text)
      assert_equal "kit-1", result.dig(:structuredContent, "id")
      assert rejected[:isError]
      assert_includes rejected.dig(:content, 0, :text), "Unknown type McpTestKits::Kit"
      refute_includes rejected.dig(:content, 0, :text).to_s.split("Allowed types:").last.to_s,
                      "McpTestKits::Kit"
    end
  end

  def test_named_action_schema_keeps_id_and_section_type
    with_press_kit_surface do
      tool = listed_tool("PressKit--create_section")
      schema = tool.fetch(:inputSchema)
      properties = schema.fetch(:properties)

      assert_includes schema.fetch(:required), "id"
      assert_includes schema.fetch(:required), "type"
      assert properties.key?(:id)
      assert properties.key?(:type)
      assert properties.key?(:content_type)
      assert_includes tool[:description], "type"
      refute_includes properties.fetch(:type).fetch(:description).to_s, "Access"
    end
  end

  def test_named_action_reads_root_fields_and_still_accepts_params
    with_press_kit_surface do
      root = call_tool(
        "PressKit--create_section",
        id: "kit-1",
        type: "Text",
        content_type: "body"
      )
      nested = call_tool(
        "PressKit--create_section",
        id: "kit-1",
        params: { type: "Quote", content_type: "pull" }
      )

      refute root[:isError], root.dig(:content, 0, :text)
      refute nested[:isError], nested.dig(:content, 0, :text)
      assert_equal "Text", root.dig(:structuredContent, "section_type")
      assert_equal "body", root.dig(:structuredContent, "content_type")
      assert_equal "Quote", nested.dig(:structuredContent, "section_type")
      assert_equal "pull", nested.dig(:structuredContent, "content_type")
    end
  end

  def test_named_action_root_fields_override_params
    with_press_kit_surface do
      clash = call_tool(
        "PressKit--create_section",
        id: "kit-1",
        type: "Text",
        content_type: "body",
        params: { type: "Quote", content_type: "pull" }
      )

      refute clash[:isError], clash.dig(:content, 0, :text)
      assert_equal "Text", clash.dig(:structuredContent, "section_type")
      assert_equal "body", clash.dig(:structuredContent, "content_type")
    end
  end

  def test_create_requires_parent_id_when_the_type_is_not_a_root
    with_press_kit_surface do
      created = call_tool("create", type: "PressKit", parent_id: "center-1", title: "Kit")
      schema = listed_tool("create").fetch(:inputSchema)
      clause = schema.fetch(:allOf).find { |entry| entry.dig(:if, :properties, :type, :const) == "PressKit" }
      action = listed_tool("capability_action")

      refute created[:isError], created.dig(:content, 0, :text)
      assert_includes clause.dig(:then, :required), "parent_id"
      assert_includes action[:description], "Root fields override params"
    end
  end

  def test_create_without_parent_id_raises_the_api_error
    with_press_kit_surface(custom_create: false) do
      missing = call_tool("create", type: "PressKit", title: "Kit")

      assert missing[:isError]
      assert_includes missing.dig(:content, 0, :text),
                      "parent_id is required for McpTestKits::Kit"
    end
  end

  def test_describe_and_instructions_point_at_describe_not_a_docs_tool
    with_press_kit_surface do
      described = call_tool("describe", type: "PressKit")
      listed = listed_tool("describe")
      create = listed_tool("create")
      instructions = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => { "protocolVersion" => "2025-06-18", "capabilities" => {}, "clientInfo" => { "name" => "test" } }
        },
        access_grant: @grant
      ).body.dig(:result, :instructions)

      refute described[:isError]
      refute_includes listed[:description], "docs tool"
      refute_includes listed[:description], "Call the docs"
      assert_includes create[:description], "Call describe"
      refute_includes create[:description], "Call the docs"
      assert_includes instructions, "Call describe for the type paragraph, included tools, skills, and relationships"
      refute_includes instructions, "Call the docs"
      refute_includes instructions, "AccessGrant"
    end
  end

  private

  def with_press_kit_surface(custom_create: true)
    with_isolated_api_configuration do
      recording = FakeRecording.new("kit-1", PRESS_KIT)
      @grant = press_kit_grant(recording)
      RecordingStudio.stub(:root_allowed?, ->(type) { type.to_s != PRESS_KIT }) do
        RecordingStudio.stub(:allowed_parent_types_for, lambda { |type|
          type.to_s == PRESS_KIT ? %w[McpTestKits::Center] : []
        }) do
          register_press_kit(custom_create: custom_create)
          yield
        end
      end
    end
  end

  def register_press_kit(custom_create: true)
    RecordingStudioApi.register_capability_action(
      :create_section,
      capability: :accessible,
      input_contract: {
        fields: {
          type: { type: :string, required: true, allow_blank: false },
          content_type: { type: :string, required: false }
        }
      },
      handler: lambda { |context|
        params = context.params.to_h.with_indifferent_access
        {
          json: {
            section_type: params[:type],
            content_type: params[:content_type]
          }
        }
      }
    )
    register_tree_type(
      PRESS_KIT,
      operations: %i[index show create],
      capability_actions: %i[create_section],
      writable_attributes: %i[title],
      public_name: "PressKit"
    )
    if custom_create
      RecordingStudioApi.register_resource_handler(
        PRESS_KIT,
        :create,
        handler: ->(_context) { { json: { id: "kit-1", type: "PressKit" } } }
      )
    else
      RecordingStudioApi.register_default_resource_actions!(api: :public)
    end
    RecordingStudioMcp.register_tool(
      name: "PressKit--create_section",
      type: PRESS_KIT,
      action: :create_section,
      title: "Create section",
      description: "Create a section. Send type for the section type.",
      input: {
        "type" => { description: "Section type." }
      },
      output: "the section"
    )
    ensure_tree_server(:public, extra_tools: %w[PressKit--create_section])
  end

  def press_kit_grant(recording)
    relation = FakeRelation.new(recording)
    grant = Struct.new(:api_client, :credential, :access_recording, :root_recording, :role).new(
      nil, nil, nil, nil, :admin
    )
    grant.define_singleton_method(:accessible_recordings) { |**| relation }
    grant.define_singleton_method(:authorized?) { |**| true }
    grant.define_singleton_method(:authorize!) { |**| true }
    grant
  end

  def listed_tool(name)
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
      access_grant: @grant
    )
    result.body.dig(:result, :tools).find { |tool| tool[:name] == name }
  end

  def call_tool(name, **arguments)
    RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => { "name" => name, "arguments" => arguments }
      },
      access_grant: @grant
    ).body.fetch(:result)
  end
end
