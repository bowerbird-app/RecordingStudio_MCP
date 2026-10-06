# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require "base64"
require "net/http"

class McpEventsTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    Dummy::McpEventInbox.clear!
    RecordingStudioMcp::CallbackVerifier.reset_cache!
    ActiveJob::Base.queue_adapter = :test
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "MCP Events App")
    Current.actor = @user
    @page_recording = @root_recording.record(Page) { |page| page.title = "Webhook me" }
    @secret = "whsec_#{Base64.strict_encode64('e' * 32)}"
    @url = "https://receiver.example.test/mcp_event_receiver"
  end

  teardown do
    Current.actor = nil if defined?(Current)
    Dummy::McpEventInbox.clear!
    RecordingStudioMcp::CallbackVerifier.reset_cache!
  end

  test "chatgpt can subscribe receive a signed recording.updated and unsubscribe" do
    token = issue_delegated_token
    headers = json_headers.merge(
      "Authorization" => "Bearer #{token}",
      "MCP-Protocol-Version" => "2026-07-28"
    )

    post "/recording_studio_mcp",
         params: rpc("server/discover").to_json,
         headers: headers
    assert_response :success
    assert_equal({}, JSON.parse(response.body).dig("result", "capabilities", "events"))

    post "/recording_studio_mcp",
         params: rpc("events/list").to_json,
         headers: headers
    assert_response :success
    names = JSON.parse(response.body).dig("result", "events").map { |event| event["name"] }
    assert_includes names, "recording.updated"

    created = nil
    stub_local_callback do
      post "/recording_studio_mcp",
           params: rpc(
             "events/subscribe",
             name: "recording.updated",
             arguments: { recording_id: @page_recording.id },
             delivery: { mode: "webhook", url: @url, secret: @secret },
             cursor: nil
           ).to_json,
           headers: headers
      assert_response :success, response.body
      created = JSON.parse(response.body).fetch("result")
    end
    assert created["id"].start_with?("sub_")
    assert_nil created["cursor"]
    refute created["truncated"]
    sub = RecordingStudioMcp::EventSubscription.find(created["id"])
    assert_equal @oauth_client.id.to_s, sub.owner_principal_id
    assert_equal @access_recording.id, sub.access_recording_id
    assert sub.matches_recording?(@page_recording), sub.arguments.inspect

    stub_local_callback do
      assert_performed_jobs 1, only: RecordingStudioMcp::DeliverEventWebhookJob do
        @root_recording.revise(@page_recording) { |page| page.title = "Webhook fired" }
      end
    end

    delivery = Dummy::McpEventInbox.deliveries.last
    assert delivery.verified
    assert_equal "recording.updated", delivery.body["name"]
    assert_equal @page_recording.id.to_s, delivery.body.dig("data", "recording_id")

    outsider = create_user(email: "outsider-#{SecureRandom.hex(4)}@example.com")
    _root, outsider_access = create_access_recording_for(user: outsider)
    other_client, = create_oauth_client(name: "Other MCP App")
    other_token = issue_token(user: outsider, oauth_client: other_client, access_recording: outsider_access)
    post "/recording_studio_mcp",
         params: rpc(
           "events/unsubscribe",
           name: "recording.updated",
           arguments: { recording_id: @page_recording.id },
           delivery: { mode: "webhook", url: @url }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{other_token}")
    assert_response :success
    sub = RecordingStudioMcp::EventSubscription.find(created["id"])
    assert_equal "active", sub.status

    post "/recording_studio_mcp",
         params: rpc(
           "events/unsubscribe",
           name: "recording.updated",
           arguments: { recording_id: @page_recording.id },
           delivery: { mode: "webhook", url: @url }
         ).to_json,
         headers: headers
    assert_response :success
    assert_equal "inactive", sub.reload.status
  end

  test "webhook inbox page is signed-in dummy only" do
    sign_in @user
    get mcp_event_receiver_path
    assert_response :success
    assert_includes response.body, "Webhook inbox"
  end

  private

  def stub_local_callback
    receiver = open_session
    original = RecordingStudioMcp::CallbackHttp.method(:post)
    RecordingStudioMcp::CallbackHttp.define_singleton_method(:post) do |_url, body:, headers:|
      receiver.post "/mcp_event_receiver",
                    params: body,
                    headers: {
                      "CONTENT_TYPE" => "application/json",
                      "webhook-id" => headers["webhook-id"],
                      "webhook-timestamp" => headers["webhook-timestamp"],
                      "webhook-signature" => headers["webhook-signature"],
                      "X-MCP-Subscription-Id" => headers["X-MCP-Subscription-Id"]
                    }
      status = receiver.response.status
      klass = status.between?(200, 299) ? Net::HTTPOK : Net::HTTPInternalServerError
      result = klass.new("1.1", status.to_s, "OK")
      result.instance_variable_set(:@read, true)
      result.define_singleton_method(:body) { receiver.response.body }
      result
    end
    yield
  ensure
    RecordingStudioMcp::CallbackHttp.define_singleton_method(:post, original)
  end

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end

  def issue_delegated_token(role: "view")
    issue_token(user: @user, oauth_client: @oauth_client, access_recording: @access_recording, role: role)
  end

  def issue_token(user:, oauth_client:, access_recording:, role: "view")
    pkce = pkce_pair
    approved = approve_delegated_oauth(
      oauth_client: oauth_client,
      user: user,
      access_recording: access_recording,
      role: role,
      pkce: pkce
    )
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: pkce.fetch(:verifier)
    }
    assert_response :success, response.body
    JSON.parse(response.body).fetch("access_token")
  end
end
