# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminMcpSectionTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @skill_catalog = RecordingStudioMcp.configuration.skill_catalog
    user = create_user
    _admin_root, root_recording = create_admin_root_recording
    Current.actor = user
    grant_or_bootstrap_access!(recording: root_recording, actor: user, role: :admin)
    sign_in user
    switch_to_root!(root_recording)
  end

  teardown do
    RecordingStudioMcp.configuration.update_skill_catalog { @skill_catalog }
    Current.actor = nil if defined?(Current)
  end

  test "mcp section lists the server tools skills and instructions" do
    RecordingStudioMcp.register_skill("desk-notes", path: Rails.root.join("README.md").to_s)

    get "/admin/sections/mcp"

    assert_response :success
    assert_includes response.body, "MCP"
    assert_includes response.body, "recording-studio"
    assert_includes response.body, RecordingStudioMcp::VERSION
    assert_includes response.body, "2025-06-18"
    assert_includes response.body, "/recording_studio_mcp"
    assert_includes response.body, "/.well-known/oauth-protected-resource/recording_studio_mcp"
    assert_includes response.body, "/recording_studio_oauth"
    assert_includes response.body, "list"
    assert_includes response.body, "List records"
    assert_includes response.body, "desk-notes"
    assert_includes response.body, "Registered, exposed"
    assert_includes response.body, "call tools/list again when you need a fresh list."
    assert_includes response.body, "Registered apps"
  end

  test "mcp section is defined by the gem and the host only allowlists it" do
    source_path, = Object.const_source_location("RecordingStudioMcp::Admin::McpSection")

    assert_operator source_path, :start_with?, RecordingStudioMcp::Engine.root.to_s
    assert_operator source_path, :end_with?, "lib/recording_studio_mcp/admin.rb"

    initializer = File.read(Rails.root.join("config/initializers/recording_studio_admin.rb"))
    admin_root = File.read(Rails.root.join("app/models/admin_root.rb"))

    refute_includes initializer, "class McpSection"
    refute_includes initializer, "RecordingStudioMcp::Admin"
    assert_includes admin_root, "section :mcp"
    refute_includes admin_root, "McpSection"
    assert_includes AdminRoot.recording_studio_admin_section_keys_for(nil, nil, nil), "mcp"
  end

  test "admin home links mcp beside registered apps" do
    get "/admin"

    assert_response :success
    assert_includes response.body, "MCP"
    assert_includes response.body, "Registered apps"
  end
end
