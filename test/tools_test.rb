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

  def test_read_tools_are_marked_read_only
    %w[list show describe].each do |name|
      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
      assert_equal true, tool.dig(:annotations, :readOnlyHint), name
    end
  end

  def test_create_has_no_attributes_envelope
    schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "create" }.fetch(:inputSchema)

    refute schema.fetch(:properties).key?(:attributes)
    assert_equal true, schema[:additionalProperties]
  end
end
