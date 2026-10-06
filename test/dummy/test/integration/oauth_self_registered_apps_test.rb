# frozen_string_literal: true

require "test_helper"

class OauthSelfRegisteredAppsTest < ActionDispatch::IntegrationTest
  test "API 0.6.1 ranks grants through AccessRoles without an MCP shim" do
    assert defined?(RecordingStudio::AccessRoles::ORDER)
    refute RecordingStudioMcp::Engine.respond_to?(:expose_access_roles_map)
    refute RecordingStudio::Access.respond_to?(:roles)
  end

  test "RFC 8414 path insertion advertises dummy registration" do
    get "/.well-known/oauth-authorization-server/recording_studio_oauth"

    assert_response :success
    body = JSON.parse(response.body)
    issuer = "#{request.base_url}/recording_studio_oauth"
    assert_equal issuer, body.fetch("issuer")
    assert_equal "#{issuer}/register", body.fetch("registration_endpoint")
  end

  test "Inspector can RFC 7591 register against the dummy" do
    post "/recording_studio_oauth/register",
         params: {
           client_name: "MCP Inspector",
           redirect_uris: ["http://127.0.0.1:6274/callback"],
           token_endpoint_auth_method: "none",
           grant_types: %w[authorization_code refresh_token],
           response_types: ["code"]
         },
         as: :json

    assert_response :created
    body = JSON.parse(response.body)
    client = RecordingStudioOauth::OauthClient.find_by!(client_id: body.fetch("client_id"))
    assert client.self_registered?
    refute client.confidential?
    assert_equal "none", body.fetch("token_endpoint_auth_method")
  end
end
