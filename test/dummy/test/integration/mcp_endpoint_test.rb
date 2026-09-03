# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpEndpointTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "MCP Test App")
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "unauthenticated post returns 401 with oauth protected resource metadata" do
    post "/recording_studio_mcp",
         params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
         headers: json_headers

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "resource_metadata="
    assert_includes response.headers["WWW-Authenticate"], "/.well-known/oauth-protected-resource"
    refute_includes response.headers["WWW-Authenticate"], "/recording_studio_mcp"
  end

  test "unauthenticated get returns 401 with the same discovery header" do
    get "/recording_studio_mcp"

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], 'resource_metadata="'
  end

  test "garbage bearer returns 401 invalid_token" do
    post "/recording_studio_mcp",
         params: rpc("initialize").to_json,
         headers: json_headers.merge("Authorization" => "Bearer not-a-token")

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], 'error="invalid_token"'
  end

  test "bearer from oauth token can list workspaces" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "list", arguments: { type: "Workspace" }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    payload = JSON.parse(response.body)
    records = tool_payload(payload).fetch("records")
    names = records.map { |record| record["name"] }

    assert_equal false, payload.dig("result", "isError")
    assert_includes names, @root_recording.recordable.name
  end

  test "capability_action ping is authorized through accessible" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "capability_action",
           arguments: { type: "Workspace", id: @root_recording.id, action: "ping" }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    payload = JSON.parse(response.body)
    body = tool_payload(payload)

    assert_equal false, payload.dig("result", "isError")
    assert_equal true, body["ok"]
    assert_equal @root_recording.id, body["id"]
  end

  test "authenticated get is not a json-rpc transport" do
    token = issue_delegated_token

    get "/recording_studio_mcp", headers: { "Authorization" => "Bearer #{token}" }

    assert_response :method_not_allowed
  end

  test "voided grant is rejected on the next mcp call" do
    token = issue_delegated_token
    authorization = RecordingStudioOauth::OauthAuthorization.find_by!(
      oauth_client: @oauth_client,
      manager_actor: @user
    )
    RecordingStudioOauth::Services::VoidOauthAuthorization.call(authorization: authorization)

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "list", arguments: { type: "Workspace" }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], 'error="invalid_token"'
  end

  test "list does not include a workspace outside the grant" do
    token = issue_delegated_token
    outsider = Workspace.create!(name: "Secret #{SecureRandom.hex(4)}")
    RecordingStudio.root_recording_for(outsider)

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "list", arguments: { type: "Workspace" }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    records = tool_payload(JSON.parse(response.body)).fetch("records")
    names = records.map { |record| record["name"] }
    assert_includes names, @root_recording.recordable.name
    refute_includes names, outsider.name
  end

  test "create and show go through the named api" do
    token = issue_delegated_token(role: "edit")

    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "create",
           arguments: {
             type: "Page",
             parent_id: @root_recording.id,
             title: "Created via MCP"
           }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    created = tool_payload(JSON.parse(response.body))
    id = created["id"]
    assert_equal "Created via MCP", created["title"]

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "show", arguments: { type: "Page", id: id }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    shown = tool_payload(JSON.parse(response.body))
    assert_equal "Created via MCP", shown["title"]
  end

  test "tools list names dummy types including Folder and Page" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    tools = JSON.parse(response.body).dig("result", "tools")
    names = tools.map { |tool| tool["name"] }
    list_enum = tools.find { |tool| tool["name"] == "list" }.dig("inputSchema", "properties", "type", "enum")
    describe_enum = tools.find { |tool| tool["name"] == "describe" }.dig("inputSchema", "properties", "type", "enum")

    assert_includes names, "describe"
    assert_includes list_enum, "Folder"
    assert_includes list_enum, "Page"
    assert_includes list_enum, "Workspace"
    assert_equal list_enum, describe_enum
  end

  test "describe page shows title writable" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "describe", arguments: { type: "Page" }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    payload = JSON.parse(response.body)
    described = tool_payload(payload)

    refute payload.dig("result", "isError")
    assert_includes described.fetch("writable_fields"), "title"
    assert_includes described.fetch("operations"), "create"
    refute_includes described.fetch("capability_actions"), "move"
  end

  test "list with pagination_token reaches page two when has_more" do
    token = issue_delegated_token(role: "edit")
    3.times do |index|
      post "/recording_studio_mcp",
           params: rpc(
             "tools/call",
             name: "create",
             arguments: {
               type: "Page",
               parent_id: @root_recording.id,
               title: "Paged #{index} #{SecureRandom.hex(4)}"
             }
           ).to_json,
           headers: json_headers.merge("Authorization" => "Bearer #{token}")
      assert_response :success, response.body
    end

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "list", arguments: { type: "Page", limit: 2 }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    first = tool_payload(JSON.parse(response.body))
    assert_equal true, first.dig("meta", "has_more")
    token_value = first.dig("meta", "next_pagination_token")
    refute_nil token_value
    first_ids = first.fetch("records").map { |record| record["id"] }

    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "list",
           arguments: { type: "Page", limit: 2, pagination_token: token_value }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    second = tool_payload(JSON.parse(response.body))
    second_ids = second.fetch("records").map { |record| record["id"] }
    assert second_ids.any?
    assert_empty first_ids & second_ids
  end

  test "unknown type error lists allowed types" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "list", arguments: { type: "Nope" }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload.dig("result", "isError")
    message = payload.dig("result", "content", 0, "text")
    assert_includes message, "Unknown type Nope"
    assert_includes message, "Folder"
    assert_includes message, "Page"
    assert_includes message, "Workspace"
  end

  test "mcp does not serve records when api access is disabled" do
    token = issue_delegated_token
    setting = RecordingStudioApi::ApiSetting.find_or_create_by!(key: "api")
    setting.update!(api_access_enabled: false)

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "list", arguments: { type: "Workspace" }).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :service_unavailable
    assert_equal "api_access_disabled", JSON.parse(response.body).dig("error", "code")
  ensure
    setting&.update!(api_access_enabled: true)
  end

  test "host well known protected resource still comes from oauth" do
    get "/.well-known/oauth-protected-resource"

    assert_response :success
    body = JSON.parse(response.body)
    assert_includes body.fetch("resource"), "/recording_studio_api"
    assert body.fetch("authorization_servers").any?
  end

  private

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end

  def tool_payload(payload)
    result = payload.fetch("result")
    return result.fetch("structuredContent") if result["structuredContent"].present?

    JSON.parse(result.dig("content", 0, "text"))
  end

  def issue_delegated_token(role: "view")
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      role: role,
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
    token = JSON.parse(response.body).fetch("access_token")
    assert token.start_with?("rsoauth_at_")

    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "public"
    )
    assert grant.success?
    assert_kind_of RecordingStudioOauth::OauthClient, grant.value.api_client

    token
  end
end
