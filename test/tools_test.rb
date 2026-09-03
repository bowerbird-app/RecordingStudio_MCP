# frozen_string_literal: true

require "test_helper"

class ToolsTest < Minitest::Test
  def test_names_are_the_parameterized_set
    assert_equal %w[list show create update capability_action], RecordingStudioMcp::Tools::NAMES
  end

  def test_definitions_cover_each_tool
    names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

    assert_equal RecordingStudioMcp::Tools::NAMES, names
  end

  def test_list_requires_type
    schema = RecordingStudioMcp::Tools.list_tool.fetch(:inputSchema)

    assert_equal ["type"], schema.fetch(:required)
  end
end
