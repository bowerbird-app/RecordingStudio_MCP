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
    assert_includes response.body, "same token works with MCP and the API on purpose"
    assert_includes response.body, "/assets/tailwind-"
    assert_includes response.body, "/assets/flat_pack/variables-"
  end

  test "dummy mcp docs page is not the product" do
    get docs_mcp_path

    assert_response :success
    assert_includes response.body, "/recording_studio_mcp"
    assert_includes response.body, "Dummy-only"
    assert_includes response.body, "describe"
    assert_includes response.body, "works here and with the API on purpose"
    assert_includes response.body, "Mint test token"
    assert_includes response.body, "/assets/tailwind-"
  end

  test "signed in mcp page shows a csrf protected mint form" do
    get docs_mcp_path

    assert_response :success
    assert_select "form[action=?][method=?]", docs_mcp_test_token_path, "post" do
      assert_select "input[name=?]", "authenticity_token", count: 1
      assert_select "button[type=?]", "submit"
    end
    assert_includes response.body, "Mint test token"
  end

  test "mint test token posts a real oauth bearer for seed mcp app" do
    load Rails.root.join("db/seeds.rb").to_s

    post docs_mcp_test_token_path

    assert_response :success
    assert_includes response.body, "Fresh token"
    assert_match(/rsoauth_at_[A-Za-z0-9_\-]+/, response.body)

    token = response.body[/(rsoauth_at_[A-Za-z0-9_\-]+)/, 1]
    assert token.present?

    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "public"
    )
    assert grant.success?
  end

  test "unauthenticated mint redirects to sign in" do
    sign_out @user

    post docs_mcp_test_token_path

    assert_redirected_to new_user_session_path
  end
end
