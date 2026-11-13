# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class RootSwitchDropdownTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OauthDummyHelpers

  test "sign in page uses the devise layout and is not squished by the default layout" do
    get new_user_session_path

    assert_response :success
    assert_includes response.body, "admin@admin.com"
    assert_includes response.body, "Password"
    assert_includes response.body, 'data-theme="rounded"'
    refute_includes response.body, "data-recording-studio-default-layout"
    refute_includes response.body, "mt-28"
    refute_includes response.body, "fixed inset-0"
  end

  test "home page renders the root switch dropdown trigger" do
    user = sign_in_switch_user("root-switch-test@example.com")
    grant_workspace_view!(name: "Dropdown Workspace", actor: user)

    get root_path

    assert_response :success
    assert_includes response.body, "Dropdown Workspace"
    assert_includes response.body, "flat-pack-sidebar-layout"
  end

  test "root switch page renders with the host default layout" do
    user = sign_in_switch_user("root-switch-page-test@example.com")
    root_recording = grant_workspace_view!(name: "Switch Page Workspace", actor: user)

    with_default_switch_root(root_recording) do
      get "/recording_studio_root_switchable/v1/root_switch?scope=all_workspaces"
    end

    assert_response :success
    assert_includes response.body, "flat-pack-sidebar-layout"
  end

  test "root switch page refuses a signed-in person without a view grant" do
    owner = sign_in_switch_user("root-switch-owner@example.com")
    grant_workspace_view!(name: "Private Workspace", actor: owner)
    sign_out owner

    visitor = sign_in_switch_user("root-switch-visitor@example.com")
    Current.actor = visitor

    get "/recording_studio_root_switchable/v1/root_switch?scope=all_workspaces"

    assert_response :forbidden
  end

  test "switching returns to the current page when it is a valid internal route" do
    user = sign_in_switch_user("root-switch-redirect-test@example.com")
    source_root_recording = grant_workspace_view!(name: "Source Workspace", actor: user)
    target_root_recording = grant_workspace_view!(name: "Target Workspace", actor: user)

    with_default_switch_root(source_root_recording) do
      patch "/recording_studio_root_switchable/v1/root_switch", params: {
        scope: "all_workspaces",
        root_switch: {
          root_recording_id: target_root_recording.id,
          return_to: "/docs/install"
        }
      }
    end

    assert_redirected_to "/docs/install"
  end

  test "switching falls back to home when return_to is not a valid internal route" do
    user = sign_in_switch_user("root-switch-fallback-test@example.com")
    source_root_recording = grant_workspace_view!(name: "Fallback Source Workspace", actor: user)
    target_root_recording = grant_workspace_view!(name: "Fallback Target Workspace", actor: user)

    with_default_switch_root(source_root_recording) do
      patch "/recording_studio_root_switchable/v1/root_switch", params: {
        scope: "all_workspaces",
        root_switch: {
          root_recording_id: target_root_recording.id,
          return_to: "/not-a-real-route"
        }
      }
    end

    assert_redirected_to "/"
  end

  private

  def sign_in_switch_user(email)
    user = User.find_or_create_by!(email: email) do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    sign_in user
    Current.actor = user
    user
  end

  def grant_workspace_view!(name:, actor:)
    owner = User.create!(
      email: "workspace-owner-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = owner
    workspace = Workspace.create!(name: name)
    root_recording = RecordingStudio.root_recording_for(workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: root_recording,
      actor: owner
    )
    raise bootstrap.error if bootstrap.failure?

    result = RecordingStudioAccessible.grant_access(
      recording: root_recording,
      actor: actor,
      role: "view",
      manager_actor: owner
    )
    raise result.error unless result.success?

    Current.actor = actor
    root_recording
  end
end
