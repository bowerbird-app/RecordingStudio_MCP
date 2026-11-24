# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpServerParentTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @root_recording, = create_access_recording_for(user: @user)
    Current.actor = @user
    @previous_enabled = RecordingStudioMcp.configuration.documentation_enabled
    @previous_access = RecordingStudioMcp.configuration.documentation_access
    RecordingStudioMcp.configuration.documentation_enabled = true
    RecordingStudioMcp.configuration.documentation_access = :authenticated
  end

  teardown do
    RecordingStudioMcp.configuration.documentation_enabled = @previous_enabled
    RecordingStudioMcp.configuration.documentation_access = @previous_access
    Current.actor = nil if defined?(Current)
  end

  test "file desk note leaves parent_id out of tools list describe docs and a call" do
    token = client_credentials_token
    listed = tools_list(token).find { |tool| tool.fetch("name") == "file_desk_note" }
    schema = listed.fetch("inputSchema")

    refute schema.fetch("properties").key?("parent_id")
    refute_includes schema.fetch("required"), "parent_id"
    assert schema.dig("properties", "note")

    described = tool_payload(post_tool(token, "describe", type: "Workspace"))
    action = described.fetch("capability_actions").find { |item| item["name"] == "file_desk_note" }
    refute action.dig("params", "fields").key?("parent_id")
    assert action.dig("params", "fields", "note")

    sign_in @user
    get "/admin/public-api/mcp-docs/openapi.json"
    assert_response :success
    spec = JSON.parse(response.body)
    documented = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "file_desk_note" }
    refute documented.dig("inputSchema", "properties").key?("parent_id")
    intro = spec.fetch("tags").find { |tag| tag["name"] == "Workspace" }.fetch("description")
    refute_match(/file_desk_note.*parent_id/, intro)

    filed = tool_payload(post_tool(token, "file_desk_note", id: @root_recording.id, note: "Desk", parent_id: "not-a-parent"))
    omitted = tool_payload(post_tool(token, "file_desk_note", id: @root_recording.id, note: "Again"))
    generic = tool_payload(post_tool(
      token,
      "capability_action",
      type: "Workspace",
      id: @root_recording.id,
      action: "file_desk_note",
      params: { note: "From the generic tool", parent_id: "still-not-a-parent" }
    ))

    assert_equal @root_recording.id.to_s, filed.fetch("parent_id")
    assert_equal "Desk", filed.fetch("title")
    assert_equal @root_recording.id.to_s, omitted.fetch("parent_id")
    assert_equal @root_recording.id.to_s, generic.fetch("parent_id")
    assert_equal 3, RecordingStudio::Recording.where(recordable_type: "Page", parent_recording_id: @root_recording.id).where("id IN (?)", [filed["id"], omitted["id"], generic["id"]]).count
  end

  private

  def tools_list(token)
    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    JSON.parse(response.body).dig("result", "tools")
  end

  def post_tool(token, name, arguments)
    post "/recording_studio_mcp",
         params: rpc("tools/call", name: name, arguments: arguments).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    body = JSON.parse(response.body)
    refute body.dig("result", "isError"), body.dig("result", "content", 0, "text")
    body
  end

  def tool_payload(body)
    content = body.dig("result", "structuredContent")
    return content if content.is_a?(Hash)

    JSON.parse(body.dig("result", "content", 0, "text"))
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def client_credentials_token
    provisioned = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: @root_recording,
      manager_actor: @user,
      role: "admin",
      name: "MCP client #{SecureRandom.hex(4)}"
    )
    assert provisioned.success?, provisioned.error

    credential = provisioned.value.fetch(:credential)
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: credential.oauth_client_id,
      client_secret: provisioned.value.fetch(:token)
    )
    assert issued.success?, issued.error

    issued.value.fetch(:access_token)
  end
end
