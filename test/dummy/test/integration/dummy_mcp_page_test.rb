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
    assert_includes response.body, "Try MCP"
    assert_includes response.body, "sample POST"
    assert_includes response.body, "/assets/tailwind-"
  end

  test "signed in mcp page shows a csrf protected mint form" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get docs_mcp_path

    assert_response :success
    assert_select "form[action=?][method=?]", docs_mcp_test_token_path, "post" do
      assert_select "input[name=?]", "authenticity_token", count: 1
      assert_select "button[type=?]", "submit"
    end
    assert_includes response.body, "Try MCP"
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "mint test token posts a real oauth bearer for seed mcp app" do
    load Rails.root.join("db/seeds.rb").to_s

    post docs_mcp_test_token_path

    assert_response :success
    assert_includes response.body, "MCP answered"
    assert_includes response.body, "Test token"
    assert_includes response.body, "list, show, create, update, capability_action, describe"
    assert_includes response.body, "Studio Workspace"
    assert_includes response.body, "Sample POST"
    assert_match(/rsoauth_at_[A-Za-z0-9_-]+/, response.body)
    refute_includes response.body, ">Try MCP<"

    token = response.body[/(rsoauth_at_[A-Za-z0-9_-]+)/, 1]
    assert token.present?

    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "public"
    )
    assert grant.success?
  end

  test "sample post hits recording studio mcp with the minted bearer" do
    load Rails.root.join("db/seeds.rb").to_s

    post docs_mcp_test_token_path
    assert_response :success
    token = response.body[/(rsoauth_at_[A-Za-z0-9_-]+)/, 1]
    assert token.present?

    post docs_mcp_sample_post_path, params: { test_token: token }

    assert_response :success
    assert_includes response.body, "Sample POST worked"
    assert_includes response.body, "Grant: <code>resolved</code>"
    assert_includes response.body, "list, show, create, update, capability_action, describe"
    refute_includes response.body, ">Sample POST<"
  end

  test "sample post without a token asks you to try mcp first" do
    post docs_mcp_sample_post_path, params: { test_token: "" }

    assert_response :unprocessable_entity
    assert_includes response.body, "Need a test token first"
  end

  test "unauthenticated mint redirects to sign in" do
    sign_out @user

    post docs_mcp_test_token_path

    assert_redirected_to new_user_session_path
  end
end
