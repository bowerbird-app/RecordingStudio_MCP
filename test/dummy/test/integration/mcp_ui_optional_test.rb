# frozen_string_literal: true

require "test_helper"

class McpUiOptionalTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers

  setup do
    @user = create_user
    _root, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "MCP UI Optional App")
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "dummy boots without MCP UI and existing tools stay plain" do
    refute defined?(RecordingStudio::MCP_UI)
    refute RecordingStudioMcp::McpUi.loaded?

    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: json_headers("Authorization" => "Bearer #{issue_token}")

    assert_response :success
    tools = JSON.parse(response.body).dig("result", "tools")
    ping = tools.find { |tool| tool["name"] == "ping" }

    assert ping
    refute ping.key?("_meta")
  end

  test "resources list has no ui scheme without MCP UI" do
    post "/recording_studio_mcp",
         params: rpc("resources/list").to_json,
         headers: json_headers("Authorization" => "Bearer #{issue_token}")

    assert_response :success
    resources = JSON.parse(response.body).dig("result", "resources") || []
    refute(resources.any? { |entry| entry["uri"].to_s.start_with?("ui://") })
  end

  def issue_token
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      role: "view",
      pkce: @pkce
    )
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    }
    assert_response :success, response.body
    JSON.parse(response.body).fetch("access_token")
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end

  def json_headers(extra = {})
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }.merge(extra)
  end
end
