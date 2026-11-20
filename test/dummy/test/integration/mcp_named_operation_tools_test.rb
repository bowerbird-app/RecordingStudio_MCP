# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpNamedOperationToolsTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  LEAF_SERIALIZER = ->(recordable, **) { { title: recordable.title } }

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @oauth_client, = create_oauth_client(name: "MCP named operations app")
    RecordingStudioApi.register_recordable_type_api(
      "Dummy::Leaf",
      serializer: LEAF_SERIALIZER,
      output_keys: %i[title],
      writable_attributes: %i[title],
      operations: %i[index show create update]
    )
    RecordingStudioApi.register_default_resource_actions!(api: :public)
    RecordingStudioMcp.register_type(
      type: "Dummy::Leaf",
      description: "A leaf under a workspace. Call describe before you write."
    )
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "named create and show succeed when the class name differs from the public name" do
    RecordingStudioMcp.register_tool(
      name: "Leaf--create",
      type: "Dummy::Leaf",
      operation: :create,
      title: "Create leaf",
      description: "Create a leaf.",
      input: {},
      output: "the leaf"
    )
    RecordingStudioMcp.register_tool(
      name: "Leaf--show",
      type: "Dummy::Leaf",
      operation: :show,
      title: "Show leaf",
      description: "Show a leaf.",
      input: {},
      output: "the leaf"
    )
    RecordingStudioMcp.register_server(:public, api: :public) do
      include_tools "Leaf--create", "Leaf--show", :ping, :demo_progress, "Workspace--ping"
    end

    token = client_credentials_token
    listed = tools_list(token).map { |tool| tool.fetch("name") }

    assert_includes listed, "Leaf--create"
    assert_includes listed, "Leaf--show"
    refute_includes listed, "create"
    refute_includes listed, "show"

    created = post_tool(
      token,
      "Leaf--create",
      parent_id: @root_recording.id.to_s,
      title: "Named leaf"
    )
    refute created.dig("result", "isError"), created.to_json
    id = created.dig("result", "structuredContent", "id")
    assert id.present?
    assert_equal "Leaf", created.dig("result", "structuredContent", "type")

    shown = post_tool(token, "Leaf--show", id: id)
    refute shown.dig("result", "isError"), shown.to_json
    assert_equal id, shown.dig("result", "structuredContent", "id")
    assert_equal "Leaf", shown.dig("result", "structuredContent", "type")

    %w[create show list capability_action].each do |name|
      body = post_tool(token, name, type: "Leaf", id: id, parent_id: @root_recording.id.to_s, title: "Nope")

      assert_equal true, body.dig("result", "isError"), name
      assert_includes body.dig("result", "content", 0, "text"), "Unknown tool #{name}"
    end
  end

  test "generic create rejects the class name and does not write a record" do
    RecordingStudioMcp.register_server(:public, api: :public) do
      include_tools :list, :show, :create, :update, :capability_action, :ping, :demo_progress,
                    "Workspace--ping"
    end

    token = client_credentials_token
    listed = tools_list(token).map { |tool| tool.fetch("name") }

    assert_includes listed, "create"

    before = RecordingStudio::Recording.where(recordable_type: "Dummy::Leaf").count
    body = post_tool(
      token,
      "create",
      type: "Dummy::Leaf",
      parent_id: @root_recording.id.to_s,
      title: "Class name leaf"
    )

    assert_equal true, body.dig("result", "isError")
    assert_includes body.dig("result", "content", 0, "text"), "Unknown type Dummy::Leaf"
    assert_equal before, RecordingStudio::Recording.where(recordable_type: "Dummy::Leaf").count
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
