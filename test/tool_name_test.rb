# frozen_string_literal: true

require "test_helper"

class ToolNameTest < Minitest::Test
  def test_show_uses_action_then_singular_snake_type
    assert_equal "show_press_kit", RecordingStudioMcp.tool_name("PressKit", :show)
  end

  def test_feature_on_press_kit_is_feature_press_kit
    assert_equal "feature_press_kit", RecordingStudioMcp.tool_name("PressKit", "feature")
  end

  def test_list_uses_the_plural_snake_form
    assert_equal "list_press_kits", RecordingStudioMcp.tool_name("PressKit", :list)
    assert_equal "list_press_kits", RecordingStudioMcp.tool_name("PressKit", :index)
  end

  def test_destroy_uses_the_delete_verb
    assert_equal "delete_press_kit", RecordingStudioMcp.tool_name("PressKit", :destroy)
  end

  def test_action_that_already_ends_with_the_type_noun_is_not_repeated
    assert_equal "add_image", RecordingStudioMcp.tool_name("Images", :add_image)
    assert_equal "add_file", RecordingStudioMcp.tool_name("RecordingStudioPresskits::Files", :add_file)
  end

  def test_trailing_action_words_that_match_leading_type_words_are_not_repeated
    assert_equal "add_quote_section", RecordingStudioMcp.tool_name("QuoteSection", :add_quote)
  end

  def test_namespaced_type_uses_the_api_public_name_when_registered
    with_isolated_api_configuration do
      register_tree_type("McpTestKits::Kit", public_name: "PressKit")

      assert_equal "show_press_kit", RecordingStudioMcp.tool_name("McpTestKits::Kit", :show)
      assert_equal "list_press_kits", RecordingStudioMcp.tool_name("McpTestKits::Kit", :index)
    end
  end
end
