# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpProgressTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "MCP Progress App")
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "demo_progress streams notifications then the original request id" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "demo_progress",
           arguments: {},
           _meta: { progressToken: "walk-1" }
         ).to_json,
         headers: sse_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    assert_equal "text/event-stream", response.media_type
    events = sse_events(response.body)
    progress = events.select { |event| event["method"] == "notifications/progress" }
    final = events.last

    assert_equal 5, progress.length
    progress.each do |event|
      refute event.key?("id")
      assert_equal "walk-1", event.dig("params", "progressToken")
    end
    assert_equal events.first.dig("jsonrpc"), "2.0"
    assert final.key?("id")
    assert_equal false, final.dig("result", "isError")
    assert_equal true, final.dig("result", "structuredContent", "completed")
  end

  test "a call without a token stays json and emits no progress" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc("tools/call", name: "demo_progress", arguments: {}).to_json,
         headers: json_headers.merge(
           "Authorization" => "Bearer #{token}",
           "Accept" => "application/json, text/event-stream"
         )

    assert_response :success
    assert_equal "application/json", response.media_type
    payload = JSON.parse(response.body)
    refute payload["method"]
    assert_equal false, payload.dig("result", "isError")
    assert_equal true, payload.dig("result", "structuredContent", "completed")
    refute_includes response.body, "notifications/progress"
  end

  test "tools/list with sse accept stays json" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc("tools/list").to_json,
         headers: sse_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    assert_equal "application/json", response.media_type
    names = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }
    assert_includes names, "demo_progress"
    assert_includes names, "describe"
  end

  test "unauthorized stream attempts are rejected as json before sse starts" do
    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "demo_progress",
           arguments: {},
           _meta: { progressToken: "nope" }
         ).to_json,
         headers: sse_headers

    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert_equal "unauthorized", JSON.parse(response.body).fetch("error")
    refute_includes response.body, "event: message"
  end

  test "disabled api is rejected as json before sse starts" do
    token = issue_delegated_token
    setting = RecordingStudioApi::ApiSetting.find_or_create_by!(key: "api")
    setting.update!(api_access_enabled: false)

    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "demo_progress",
           arguments: {},
           _meta: { progressToken: "nope" }
         ).to_json,
         headers: sse_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :service_unavailable
    assert_equal "application/json", response.media_type
    assert_equal "api_access_disabled", JSON.parse(response.body).dig("error", "code")
  ensure
    setting&.update!(api_access_enabled: true)
  end

  test "a streamed call writes one usage row and does not store the token" do
    token = issue_delegated_token

    assert_difference -> { RecordingStudioMcp::UsageLog.where(subject_name: "demo_progress").count }, 1 do
      post "/recording_studio_mcp",
           params: rpc(
             "tools/call",
             name: "demo_progress",
             arguments: { secret: "not-logged" },
             _meta: { progressToken: "usage-token" }
           ).to_json,
           headers: sse_headers.merge("Authorization" => "Bearer #{token}")
    end

    assert_response :success
    log = RecordingStudioMcp::UsageLog.where(subject_name: "demo_progress").order(:occurred_at).last
    assert_equal "tools/call", log.method_name
    assert_equal @oauth_client.id, log.api_client_id
    refute log.failed
    refute_includes log.attributes.values.map(&:to_s).join, "usage-token"
    refute_includes log.attributes.values.map(&:to_s).join, "not-logged"
  end

  test "a wrong type progress token still runs the tool as json" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc(
           "tools/call",
           name: "demo_progress",
           arguments: {},
           _meta: { progressToken: { nested: true } }
         ).to_json,
         headers: sse_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    assert_equal "application/json", response.media_type
    payload = JSON.parse(response.body)
    assert_equal true, payload.dig("result", "structuredContent", "completed")
  end

  private

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def sse_headers
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: 42, method: method, params: params }
  end

  def sse_events(body)
    body.to_s.split("\n\n").filter_map do |block|
      line = block.lines.map(&:rstrip).find { |entry| entry.start_with?("data: ") }
      next unless line

      JSON.parse(line.delete_prefix("data: "))
    end
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
    JSON.parse(response.body).fetch("access_token")
  end
end
