# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class DummySidebarTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
    end
    sign_in @user
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "signed in pages use a FlatPack sidebar with home, pages, try mcp, registered apps, and sign out" do
    get root_path

    assert_response :success
    assert_includes response.body, "flat-pack-sidebar-layout"
    refute_includes response.body, "data-recording-studio-default-layout"
    assert_select "nav[aria-label='Main navigation']" do
      assert_select "a[href=?]", root_path
      assert_select "a[href=?]", pages_path
      assert_select "a[href=?]", docs_mcp_path
      assert_select "a[href=?]", "/admin/screens/oauth_clients"
    end
    assert_includes response.body, "Home"
    assert_includes response.body, "Pages"
    assert_includes response.body, "Try MCP"
    assert_includes response.body, "Registered apps"
    assert_select "a[href=?][data-turbo-method=?]", destroy_user_session_path, "delete"

    get docs_mcp_path

    assert_response :success
    assert_includes response.body, "flat-pack-sidebar-layout"
    assert_includes response.body, "Try MCP"
    assert_select "a[href=?]", "/admin/screens/oauth_clients"
  end

  test "oauth registered apps screen lists seed and dynamically registered mcp clients" do
    load Rails.root.join("db/seeds.rb").to_s
    _admin_root, admin_root_recording = create_admin_root_recording
    grant_or_bootstrap_access!(recording: admin_root_recording, actor: @user, role: :admin)
    switch_to_root!(admin_root_recording)

    dcr_client, = create_oauth_client(
      name: "Cursor",
      redirect_uris: ["https://cursor.com/oauth/callback"]
    )

    get "/admin/screens/oauth_clients"

    assert_response :success
    assert_includes response.body, "Registered apps"
    assert_includes response.body, "New app"
    assert_includes response.body, "/recording_studio_oauth/admin/oauth_clients/new"

    get "/admin/screens/oauth_clients/table",
        params: { anchor_url: "http://www.example.com/admin/screens/oauth_clients" }

    assert_response :success
    assert_includes response.body, "Seed MCP App"
    assert_includes response.body, "Cursor"
    assert_includes response.body, "Public"
    assert_includes response.body, "Active"
    assert RecordingStudioOauth::OauthClient.exists?(id: dcr_client.id, name: "Cursor")
  end

  test "unauthenticated home redirects to sign in" do
    sign_out @user

    get root_path

    assert_redirected_to new_user_session_path
  end
end
