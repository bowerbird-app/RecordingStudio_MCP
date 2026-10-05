# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpSubscriptionsTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "MCP Watch App")
    Current.actor = @user
    @page_recording = @root_recording.record(Page) { |page| page.title = "Watch me" }
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "resources list and read are scoped to the grant" do
    token = issue_delegated_token
    uri = "recording://#{@page_recording.id}"

    post "/recording_studio_mcp",
         params: rpc("resources/list").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    uris = JSON.parse(response.body).dig("result", "resources").map { |entry| entry["uri"] }
    assert_includes uris, uri

    post "/recording_studio_mcp",
         params: rpc("resources/read", uri: uri).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    text = JSON.parse(response.body).dig("result", "contents", 0, "text")
    assert_includes text, "Watch me"

    outsider = Workspace.create!(name: "Secret #{SecureRandom.hex(4)}")
    secret_root = RecordingStudio.root_recording_for(outsider)
    post "/recording_studio_mcp",
         params: rpc("resources/read", uri: "recording://#{secret_root.id}").to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_equal(-32_002, JSON.parse(response.body).dig("error", "code"))
  end

  test "legacy get stream delivers resources updated after a saved change" do
    token = issue_delegated_token
    uri = "recording://#{@page_recording.id}"
    session = open_legacy_session(token)

    post "/recording_studio_mcp",
         params: rpc("resources/subscribe", uri: uri).to_json,
         headers: json_headers.merge(
           "Authorization" => "Bearer #{token}",
           "MCP-Protocol-Version" => "2025-06-18",
           "Mcp-Session-Id" => session
         )

    assert_response :success, response.body
    assert_equal({}, JSON.parse(response.body)["result"])

    finisher = Thread.new do
      sleep 0.2
      Current.actor = @user
      @root_recording.revise(@page_recording) { |page| page.title = "Changed for watchers" }
      sleep 0.4
      RecordingStudioMcp::Connections.fetch(session)&.finish!
    end

    get "/recording_studio_mcp",
        headers: {
          "Authorization" => "Bearer #{token}",
          "Accept" => "text/event-stream",
          "MCP-Protocol-Version" => "2025-06-18",
          "Mcp-Session-Id" => session
        }

    finisher.join
    assert_response :success
    assert_equal "text/event-stream", response.media_type
    events = sse_events(response.body)
    updated = events.find { |event| event["method"] == "notifications/resources/updated" }
    assert_equal uri, updated.dig("params", "uri")
    refute updated.dig("params", "_meta")
  end

  test "modern listen acknowledges then notifies with subscription id" do
    token = issue_delegated_token
    uri = "recording://#{@page_recording.id}"

    finisher = Thread.new do
      sleep 0.2
      Current.actor = @user
      @root_recording.revise(@page_recording) { |page| page.title = "Modern change" }
      sleep 0.4
      RecordingStudioMcp::Connections.each(&:finish!)
    end

    post "/recording_studio_mcp",
         params: {
           jsonrpc: "2.0",
           id: 4,
           method: "subscriptions/listen",
           params: {
             notifications: { resourceSubscriptions: [uri] },
             _meta: { "io.modelcontextprotocol/protocolVersion" => "2026-07-28" }
           }
         }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json, text/event-stream",
           "Authorization" => "Bearer #{token}",
           "MCP-Protocol-Version" => "2026-07-28",
           "Mcp-Method" => "subscriptions/listen"
         }

    finisher.join
    assert_response :success
    events = sse_events(response.body)
    ack = events.find { |event| event["method"] == "notifications/subscriptions/acknowledged" }
    updated = events.find { |event| event["method"] == "notifications/resources/updated" }

    assert_equal [uri], ack.dig("params", "notifications", "resourceSubscriptions")
    assert_equal 4, ack.dig("params", "_meta", "io.modelcontextprotocol/subscriptionId")
    assert_equal uri, updated.dig("params", "uri")
    assert_equal 4, updated.dig("params", "_meta", "io.modelcontextprotocol/subscriptionId")
    completion = events.find { |event| event["id"] == 4 && event["result"] }
    assert_equal "complete", completion.dig("result", "resultType")
  end

  test "postgres notify payload reaches a second listener then local subscribers" do
    skip "Postgres LISTEN/NOTIFY needs a live Postgres adapter" unless RecordingStudioMcp::PostgresBus.enabled?

    RecordingStudioMcp::PostgresBus.start!
    recording_id = @page_recording.id
    uri = "recording://#{recording_id}"
    grant = Object.new
    grant.define_singleton_method(:accessible_recordings) do
      RecordingStudio::Recording.where(id: recording_id)
    end
    connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
    connection.subscribe(uri)

    received = Queue.new
    listen_connection = ActiveRecord::Base.connection_pool.checkout
    listen_thread = Thread.new do
      listen_connection.execute("LISTEN #{RecordingStudioMcp::PostgresBus::CHANNEL}")
      listen_connection.raw_connection.wait_for_notify(3) do |_channel, _pid, payload|
        received << payload
      end
    end
    sleep 0.1
    RecordingStudioMcp::Fanout.publish(event_name: "recording updated", recording_id: @page_recording.id)
    listen_thread.join(4)
    payload = received.pop(true)
    parsed = JSON.parse(payload)

    assert_equal "recording updated", parsed["event"]
    assert_equal @page_recording.id.to_s, parsed["id"]
    wait_until { connection.pending? }
    assert connection.pending?
  ensure
    if defined?(listen_connection) && listen_connection
      listen_connection.execute("UNLISTEN #{RecordingStudioMcp::PostgresBus::CHANNEL}")
      ActiveRecord::Base.connection_pool.checkin(listen_connection)
    end
  end

  test "initialize advertises subscribe because dummy registered recording updated" do
    token = issue_delegated_token

    post "/recording_studio_mcp",
         params: rpc(
           "initialize",
           protocolVersion: "2025-06-18",
           capabilities: {},
           clientInfo: { name: "test" }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body.dig("result", "capabilities", "resources", "subscribe")
    assert response.headers["Mcp-Session-Id"].present?
  end

  private

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end

  def sse_events(body)
    body.to_s.split("\n\n").filter_map do |block|
      line = block.lines.map(&:rstrip).find { |entry| entry.start_with?("data: ") }
      next unless line

      JSON.parse(line.delete_prefix("data: "))
    end
  end

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if yield
      raise "timed out waiting" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end

  def open_legacy_session(token)
    post "/recording_studio_mcp",
         params: rpc(
           "initialize",
           protocolVersion: "2025-06-18",
           capabilities: {},
           clientInfo: { name: "legacy-watch" }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    response.headers.fetch("Mcp-Session-Id")
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
