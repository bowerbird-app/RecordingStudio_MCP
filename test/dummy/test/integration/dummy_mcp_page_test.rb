# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class DummyMcpPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
    end
    sign_in @user
  end

  test "home page shows the dummy mcp url" do
    get root_path

    assert_response :success
    assert_includes response.body, "/recording_studio_mcp"
    assert_includes response.body, "/assets/tailwind-"
    assert_includes response.body, "/assets/flat_pack/variables-"
  end

  test "dummy mcp docs page is not the product" do
    get docs_mcp_path

    assert_response :success
    assert_includes response.body, "/recording_studio_mcp"
    assert_includes response.body, "Dummy-only"
    assert_includes response.body, "/assets/tailwind-"
  end
end
