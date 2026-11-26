# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpToolsListRolesTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @viewer = create_user(email: "viewer-#{SecureRandom.hex(4)}@example.com")
    @editor = create_user(email: "editor-#{SecureRandom.hex(4)}@example.com")
    @view_access = grant_role!(@viewer, "view")
    @edit_access = grant_role!(@editor, "edit")
    @oauth_client, = create_oauth_client(name: "Public MCP roles")
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "view edit and admin grants on the public server list the same tools" do
    view = tool_names(issue_token(@view_access, "view"))
    edit = tool_names(issue_token(@edit_access, "edit"))
    admin = tool_names(issue_token(@access_recording, "admin"))

    assert_equal view, edit
    assert_equal view, admin
    assert_includes view, "create"
    assert_includes view, "update"
    assert_includes view, "capability_action"
    refute_includes view, "delete"
    refute_includes view, "ops_ping"
    refute_includes view, "operations_metrics_index"
    refute_includes view, "operations_metrics_show"
    RecordingStudioMcp::McpCopy.tool_names.each do |name|
      refute_includes view, name
    end
  end

  private

  def grant_role!(actor, role)
    Current.actor = @user
    result = RecordingStudioAccessible.grant_access(
      recording: @root_recording,
      actor: actor,
      role: role,
      manager_actor: @user
    )
    raise result.error unless result.success?

    result.value
  end

  def tool_names(token)
    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    JSON.parse(response.body).dig("result", "tools").map { |tool| tool.fetch("name") }
  end

  def issue_token(access_recording, role)
    pkce = pkce_pair
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: access_recording,
      role: role,
      pkce: pkce
    )
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: pkce.fetch(:verifier)
    }
    assert_response :success, response.body
    JSON.parse(response.body).fetch("access_token")
  end

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end
end
