# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class OpsMcpAuthorizeTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @pkce = pkce_pair
    @ops_client, = create_oauth_client(name: "Ops MCP App", api: "operations")
    @public_client, = create_oauth_client(name: "Public MCP App")
    _admin_root, @admin_root_recording = create_admin_root_recording
    @admin_root_access = grant_or_bootstrap_access!(
      recording: @admin_root_recording,
      actor: @user,
      role: :admin
    )
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "ops mcp metadata uses the operations authorize issuer not the public one" do
    get "/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "#{request.base_url}/recording_studio_mcp/apis/operations", body.fetch("resource")
    refute_includes body.fetch("resource"), "recording_studio_api"
    assert_equal ["#{request.base_url}/recording_studio_oauth/apis/operations"], body.fetch("authorization_servers")
  end

  test "public mcp metadata is unchanged" do
    get "/.well-known/oauth-protected-resource/recording_studio_mcp"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "#{request.base_url}/recording_studio_mcp", body.fetch("resource")
    assert_equal ["#{request.base_url}/recording_studio_oauth"], body.fetch("authorization_servers")
  end

  test "unauthenticated ops mcp 401 points at ops protected resource metadata" do
    post named_mcp_path("operations"),
         params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
         headers: json_headers

    assert_response :unauthorized
    www = response.headers["WWW-Authenticate"]
    assert_includes www, "/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations"
    refute_includes www, 'resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/recording_studio_mcp"'
  end

  test "public mcp 401 still points at public mcp metadata" do
    post "/recording_studio_mcp",
         params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
         headers: json_headers

    assert_response :unauthorized
    www = response.headers["WWW-Authenticate"]
    assert_includes www, "/.well-known/oauth-protected-resource/recording_studio_mcp"
    refute_includes www, "/apis/operations"
  end

  test "ops authorize plus operations token lists operations tools on the ops mcp path" do
    sign_in @user
    resource = "http://www.example.com/recording_studio_mcp/apis/operations"
    params = authorize_params(client: @ops_client, resource: resource)
    unless RecordingStudioOauth.protected_resources(api_key: "operations").permit?(
      resource, base_url: "http://www.example.com"
    )
      # Oauth #25 still registers only the operations API identifier, not MCP.
      params.delete(:resource)
    end

    get named_authorize_path("operations"), params: params

    assert_response :success
    assert_includes response.body, @admin_root_recording.recordable.name

    post named_authorize_path("operations"), params: params.merge(
      access_recording_id: @admin_root_access.id,
      role: "view",
      decision: "connect"
    )

    assert_response :redirect
    code = URI.decode_www_form(URI.parse(response.redirect_url).query.to_s).to_h.fetch("code")

    token_params = {
      grant_type: "authorization_code",
      client_id: @ops_client.client_id,
      code: code,
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    }
    token_params[:resource] = resource if params[:resource].present?

    post named_api_token_path("operations"), params: token_params

    assert_response :success, response.body
    token = JSON.parse(response.body).fetch("access_token")
    assert token.start_with?("rsoauth_at_")

    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "operations"
    )
    assert grant.success?
    assert_equal "operations", grant.value.api_client.api_key
    assert_equal @admin_root_recording.id, grant.value.root_recording.id

    post named_mcp_path("operations"),
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    names = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }
    assert_includes names, "ops_ping"
    refute_includes names, "list"
  end

  test "public mcp authorize with the mcp resource identity is unchanged" do
    _root, access = create_access_recording_for(user: @user)
    sign_in @user

    get "/recording_studio_oauth/oauth/authorize", params: authorize_params(
      client: @public_client,
      resource: "http://www.example.com/recording_studio_mcp"
    ).merge(access_recording_id: access.id)

    assert_response :success
    refute_includes response.body, "invalid_target"
    assert_includes response.body, access.parent_recording.recordable.name
  end

  test "public bearer is rejected on the ops mcp path" do
    _root, access = create_access_recording_for(user: @user)
    public_token = issue_token(client: @public_client, access_recording: access)

    post named_mcp_path("operations"),
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{public_token}")

    assert_response :unauthorized
  end

  test "operations bearer is rejected on the public mcp path" do
    token = issue_token(client: @ops_client, access_recording: @admin_root_access, api: "operations")

    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :unauthorized
  end

  private

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end

  def authorize_params(client:, resource: nil)
    {
      response_type: "code",
      client_id: client.client_id,
      redirect_uri: "http://127.0.0.1/callback",
      state: "xyz",
      code_challenge: @pkce.fetch(:challenge),
      code_challenge_method: "S256",
      resource: resource
    }.compact
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
end
