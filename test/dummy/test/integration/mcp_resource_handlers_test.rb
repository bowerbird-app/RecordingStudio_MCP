# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpResourceHandlersTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @pkce = pkce_pair
    @ops_client, = create_oauth_client(name: "Ops handler MCP", api: "operations")
    _admin_root, @admin_root_recording = create_admin_root_recording(name: "Ops #{SecureRandom.hex(4)}")
    @admin_root_access = grant_or_bootstrap_access!(
      recording: @admin_root_recording,
      actor: @user,
      role: :admin
    )
    @outside_id = "support-outside-#{SecureRandom.hex(4)}"
    register_operations_support_surface!
  end

  teardown do
    restore_operations_support_surface!
    Current.actor = nil if defined?(Current)
  end

  test "ops mcp lists support types and handler tools reach records outside the admin tree" do
    token = issue_ops_token
    headers = json_headers.merge("Authorization" => "Bearer #{token}")

    post named_mcp_path("operations"), params: rpc("tools/list").to_json, headers: headers
    assert_response :success, response.body
    tools = JSON.parse(response.body).dig("result", "tools")
    names = tools.map { |tool| tool["name"] }
    list_enum = tools.find { |tool| tool["name"] == "list" }.dig("inputSchema", "properties", "type", "enum")
    delete = tools.find { |tool| tool["name"] == "delete" }

    assert_includes names, "list"
    assert_includes names, "delete"
    assert_includes list_enum, "SupportPage"
    refute_includes list_enum, "Page"
    assert delete
    assert_equal ["SupportPage"], delete.dig("inputSchema", "properties", "type", "enum")
    assert_equal true, delete.dig("annotations", "destructiveHint")

    tool_arguments = {
      "list" => { type: "SupportPage", q: "help" },
      "show" => { type: "SupportPage", id: @outside_id },
      "create" => { type: "SupportPage", title: "Hi" },
      "update" => { type: "SupportPage", id: @outside_id, title: "Hi" },
      "delete" => { type: "SupportPage", id: @outside_id }
    }
    tool_arguments.each do |tool, arguments|
      post named_mcp_path("operations"),
           params: rpc("tools/call", name: tool, arguments: arguments).to_json,
           headers: headers

      assert_response :success, response.body
      payload = JSON.parse(response.body)
      refute payload.dig("result", "isError"), "#{tool}: #{payload}"
      body = tool_payload(payload)
      assert_equal tool, body["handled"]
      assert_equal @outside_id, body["id"] if %w[show update delete].include?(tool)
    end

    post named_mcp_path("operations"),
         params: rpc(
           "tools/call",
           name: "capability_action",
           arguments: { type: "SupportPage", id: @outside_id, action: "move", params: { parent_id: "section-1" } }
         ).to_json,
         headers: headers

    assert_response :success, response.body
    moved = tool_payload(JSON.parse(response.body))
    assert_equal "move", moved["handled"]
    assert_equal @outside_id, moved["id"]

    post named_mcp_path("operations"),
         params: rpc("tools/call", name: "show", arguments: { type: "Folder", id: @outside_id }).to_json,
         headers: headers

    assert_response :success, response.body
    shown = JSON.parse(response.body)
    assert shown.dig("result", "isError")
    assert_includes shown.dig("result", "content", 0, "text"), "Resource was not found in this API scope"
  end

  test "public mcp type enum does not include operations-only support types" do
    public_client, = create_oauth_client(name: "Public handler MCP")
    _root, access = create_access_recording_for(user: @user)
    token = issue_token(client: public_client, access_recording: access)

    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    tools = JSON.parse(response.body).dig("result", "tools")
    list_enum = tools.find { |tool| tool["name"] == "list" }.dig("inputSchema", "properties", "type", "enum")
    names = tools.map { |tool| tool["name"] }

    refute_includes list_enum, "SupportPage"
    refute_includes names, "delete"
    assert_includes list_enum, "Page"
  end

  private

  def register_operations_support_surface!
    RecordingStudioApi.register_default_resource_actions!(api: :operations)
    RecordingStudioApi.register_default_capability_actions!(api: :operations)
    if RecordingStudioApi.capability_action(:move, api: :operations).nil?
      RecordingStudioApi.register_capability_action(
        :move,
        capability: :movable,
        api: :operations,
        handler: ->(_context) { { json: { fallback: true } } }
      )
    end
    RecordingStudioApi.register_recordable_type_api(
      "SupportPage",
      api: :operations,
      operations: %i[index show create update destroy],
      writable_attributes: %i[title],
      output_keys: %i[title],
      capability_actions: %i[move],
      serializer: ->(recordable, **) { { title: recordable.title } }
    )
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      api: :operations,
      operations: %i[index show],
      writable_attributes: %i[name],
      output_keys: %i[name],
      serializer: ->(recordable, **) { { name: recordable.name } }
    )

    %i[index show create update destroy].each do |action|
      RecordingStudioApi.register_resource_handler("SupportPage", action, api: :operations, handler: lambda { |context|
        { json: { handled: action == :index ? "list" : tool_name_for(action), id: context.id }, status: :ok }
      })
    end
    RecordingStudioApi.register_resource_handler("SupportPage", :move, api: :operations, handler: lambda { |context|
      { json: { handled: "move", id: context.id, parent_id: context.params[:parent_id] }, status: :accepted }
    })
  end

  def restore_operations_support_surface!
    definition = RecordingStudioApi.configuration.fetch_api(:operations)
    clear_registry(definition.recordable_registry, %w[SupportPage Folder])
    clear_handler_registry(definition.resource_handler_registry, "SupportPage")
  end

  def clear_registry(registry, types)
    store = registry.instance_variable_get(:@registrations)
    return unless store.respond_to?(:delete)

    types.each { |type| store.delete(type) }
  end

  def clear_handler_registry(registry, type)
    store = registry.instance_variable_get(:@handlers)
    return unless store.respond_to?(:delete)

    store.keys.select { |type_name, _action| type_name == type }.each { |key| store.delete(key) }
  end

  def tool_name_for(action)
    { show: "show", create: "create", update: "update", destroy: "delete" }.fetch(action)
  end

  def issue_ops_token
    issue_token(client: @ops_client, access_recording: @admin_root_access, api: "operations")
  end

  def issue_token(client:, access_recording:, api: "public")
    approved = approve_delegated_oauth(
      oauth_client: client,
      user: @user,
      access_recording: access_recording,
      pkce: @pkce
    )
    token_url = api == "public" ? "/recording_studio_api/oauth/token" : named_api_token_path(api)
    post token_url, params: {
      grant_type: "authorization_code",
      client_id: client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
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

  def tool_payload(payload)
    result = payload.fetch("result")
    return result.fetch("structuredContent") if result["structuredContent"].present?

    JSON.parse(result.dig("content", 0, "text"))
  end
end
