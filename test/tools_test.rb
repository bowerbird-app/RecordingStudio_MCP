# frozen_string_literal: true

require "test_helper"

class ToolsTest < Minitest::Test
  def test_names_are_the_parameterized_set
    assert_equal %w[list show create update capability_action describe], RecordingStudioMcp::Tools::NAMES
  end

  def test_definitions_cover_each_tool
    names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

    assert_equal RecordingStudioMcp::Tools::NAMES, names
  end

  def test_list_requires_type
    schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "list" }.fetch(:inputSchema)

    assert_equal ["type"], schema.fetch(:required)
    assert schema.fetch(:properties).key?(:pagination_token)
  end

  def test_tools_have_display_titles
    expected = {
      "list" => "List records",
      "show" => "Show a record",
      "create" => "Create a record",
      "update" => "Update a record",
      "capability_action" => "Run a capability action",
      "describe" => "Describe a type"
    }

    expected.each do |name, title|
      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
      assert_equal title, tool[:title], name
    end
  end

  def test_read_tools_are_marked_read_only
    %w[list show describe].each do |name|
      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
      assert_equal true, tool.dig(:annotations, :readOnlyHint), name
      assert_equal false, tool.dig(:annotations, :destructiveHint), name
      assert_equal true, tool.dig(:annotations, :idempotentHint), name
      assert_equal false, tool.dig(:annotations, :openWorldHint), name
    end
  end

  def test_write_tools_are_marked_as_changing_data
    create = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "create" }
    update = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "update" }
    action = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "capability_action" }

    [create, update].each do |tool|
      assert_equal false, tool.dig(:annotations, :readOnlyHint), tool[:name]
      assert_equal false, tool.dig(:annotations, :destructiveHint), tool[:name]
      assert_equal false, tool.dig(:annotations, :openWorldHint), tool[:name]
      assert_includes tool[:description], "Changes data"
    end

    assert_equal true, create.dig(:annotations, :idempotentHint)
    assert_equal false, update.dig(:annotations, :idempotentHint)

    assert_equal false, action.dig(:annotations, :readOnlyHint)
    assert_equal true, action.dig(:annotations, :destructiveHint)
    assert_equal false, action.dig(:annotations, :idempotentHint)
    assert_equal false, action.dig(:annotations, :openWorldHint)
    assert_includes action[:description], "destructively change data"
  end

  def test_create_has_no_attributes_envelope
    schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "create" }.fetch(:inputSchema)

    refute schema.fetch(:properties).key?(:attributes)
    assert_equal true, schema[:additionalProperties]
  end
end
