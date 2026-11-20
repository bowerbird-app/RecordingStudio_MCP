# frozen_string_literal: true

require "test_helper"

class ToolNameCorePluralTest < ActiveSupport::TestCase
  test "list uses the core plural label when it differs from inflector pluralize" do
    declared = RecordingStudio.recordable_type_plural_label("AdminRoot").to_s.parameterize(separator: "_")
    inflected = "AdminRoot".underscore.singularize.pluralize

    refute_equal inflected, declared
    assert_equal "list_#{declared}", RecordingStudioMcp.tool_name("AdminRoot", :index)
    assert_equal "show_admin_root", RecordingStudioMcp.tool_name("AdminRoot", :show)
  end
end
