# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpIncludeToolsFilterTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "MCP include tools app")
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "excluded generic tools are unknown and do not write records" do
    RecordingStudioMcp.register_tool(
      name: "Page--create",
      type: "Page",
      operation: :create,
      title: "Create page",
      description: "Create a page.",
      input: {},
      output: "the page"
    )
    RecordingStudioMcp.register_server(:public, api: :public) do
      include_tools "Page--create", :ping, :demo_progress, "Workspace--ping"
    end

    token = client_credentials_token
    recordings_before = RecordingStudio::Recording.count
    events_before = event_count
    listed = tools_list(token).map { |tool| tool.fetch("name") }

    refute_includes listed, "create"
    refute_includes listed, "capability_action"
    assert_includes listed, "Page--create"
    assert_includes listed, "describe"

    %w[create list show capability_action].each do |name|
      body = post_tool(token, name, type: "Page", id: @root_recording.id.to_s, action: "ping", title: "Nope")

      assert_equal true, body.dig("result", "isError"), name
      assert_includes body.dig("result", "content", 0, "text"), "Unknown tool #{name}"
    end

    assert_equal recordings_before, RecordingStudio::Recording.count
    assert_equal events_before, event_count
  end

  private

  def event_count
    RecordingStudio::Event.count
  end

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
    JSON.parse(response.body)
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
