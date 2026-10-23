# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpUsageTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user
    _workspace_root, @access_recording = create_access_recording_for(user: @user)
    _admin_root, @admin_root_recording = create_admin_root_recording
    grant_or_bootstrap_access!(recording: @admin_root_recording, actor: @user, role: :admin)
    @oauth_client, = create_oauth_client(name: "Usage App")
    @pkce = pkce_pair
  end

  teardown do
    Current.actor = nil if defined?(Current)
    RecordingStudioMcp::UsageRecorder.sink = nil
  end

  test "a tool call is logged and shown on the mcp admin section" do
    token = issue_token
    prior_calls = RecordingStudioMcp::UsageLog.where(method_name: "tools/call", subject_name: "list").count

    post "/recording_studio_mcp",
         params: {
           jsonrpc: "2.0",
           id: 1,
           method: "tools/call",
           params: { name: "list", arguments: { type: "Workspace", title: "Secret title" } }
         }.to_json,
         headers: json_headers("Authorization" => "Bearer #{token}")

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body.dig("result", "isError"), response.body
    log = RecordingStudioMcp::UsageLog.where(api_client_id: @oauth_client.id, subject_name: "list").order(:occurred_at).last
    assert_equal "tools/call", log.method_name
    assert_equal "list", log.subject_name
    assert_equal @oauth_client.id, log.api_client_id
    refute log.failed
    refute_includes log.attributes.values.map(&:to_s).join, "Secret title"

    assert_equal prior_calls + 1, RecordingStudioMcp::UsageLog.where(
      method_name: "tools/call",
      subject_name: "list"
    ).count

    sign_in @user
    switch_to_root!(@admin_root_recording)
    get "/admin/sections/mcp"

    assert_response :success
    assert_select "h3", text: "Usage"
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "/admin/screens/mcp_usage"
    assert_select "span.text-5xl", text: RecordingStudioMcp::UsageWindow.total.to_s

    get "/admin/screens/mcp_usage/table"

    assert_response :success
    assert_includes response.body, "tools/call"
    assert_includes response.body, "list"
    refute_includes response.body, "Secret title"

    get "/admin/screens/mcp_usage/chart"

    assert_response :success
    assert_includes response.body, "Last 4 weeks"

    get "/admin/screens/mcp_usage"
    assert_response :success
    assert_select "form#screen-inline-filters-form" do
      assert_select "[name='status']"
      assert_select "[name='group_by']"
      assert_select "[name='date_range_preset'], [name='start_date']"
      assert_select "[name='failed']", count: 0
      assert_select "[name='method']", count: 0
    end
    assert_select "[name='failed']"
    assert_select "[name='method']"
  end

  test "a rejected sign in is still counted" do
    assert_difference -> { RecordingStudioMcp::UsageLog.where(method_name: "ping", status_code: 401).count }, 1 do
      post "/recording_studio_mcp",
           params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
           headers: json_headers
    end

    assert_response :unauthorized
    log = RecordingStudioMcp::UsageLog.where(method_name: "ping", status_code: 401).order(:created_at).last
    assert_equal "ping", log.method_name
    assert_equal "", log.subject_name
    assert_nil log.api_client_id
    assert log.failed
    assert_equal 401, log.status_code
  end

  test "a write failure still returns the mcp response" do
    token = issue_token
    RecordingStudioMcp::UsageRecorder.sink = ->(_payload) { raise "disk full" }

    assert_no_difference -> { RecordingStudioMcp::UsageLog.count } do
      post "/recording_studio_mcp",
           params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
           headers: json_headers("Authorization" => "Bearer #{token}")
    end

    assert_response :success
  end

  test "usage logs stay until Logs retention cleanup runs" do
    RecordingStudioMcp::UsageLog.delete_all
    old = RecordingStudioMcp::UsageLog.create!(
      occurred_at: 40.days.ago,
      method_name: "initialize",
      subject_name: "",
      status_code: 200,
      duration_ms: 2,
      rate_limited: false,
      failed: false
    )

    assert_equal old.id, RecordingStudioMcp::UsageLog.find(old.id).id
  end

  test "boot registers usage logs with RecordingStudioLogs daily aggregation" do
    log = RecordingStudioLogs.registry.log_for(RecordingStudioMcp::UsageLog)
    refute_nil log
    assert_nil log.partition_interval
    assert_equal 30.days, log.declared_retention
    assert_nil log.root_column
    aggregations = RecordingStudioLogs.registry.aggregations_for(log)
    assert_equal 1, aggregations.size
    assert_equal RecordingStudioMcp::LogsRegistration::AGGREGATION_NAME, aggregations.first.name
    refute defined?(RecordingStudioMcp::UsageDaySummary)
  end

  test "Logs aggregation fills the existing daily metrics table" do
    RecordingStudioMcp::UsageLog.delete_all
    RecordingStudioMcp::UsageDailyMetric.delete_all
    day = Date.new(2026, 10, 14)
    stamp = Time.utc(2026, 10, 14, 12)
    RecordingStudioMcp::UsageLog.create!(
      occurred_at: stamp,
      method_name: "tools/call",
      subject_name: "list",
      status_code: 200,
      duration_ms: 4,
      rate_limited: false,
      failed: false
    )
    RecordingStudioMcp::UsageLog.create!(
      occurred_at: stamp,
      method_name: "tools/call",
      subject_name: "list",
      status_code: 500,
      duration_ms: 9,
      rate_limited: false,
      failed: true
    )
    RecordingStudioMcp::UsageLog.create!(
      occurred_at: stamp,
      method_name: "tools/call",
      subject_name: "show",
      status_code: 429,
      duration_ms: 2,
      rate_limited: true,
      failed: true
    )

    RecordingStudioLogs.aggregate_day!(day)
    RecordingStudioLogs.aggregate_day!(day)

    row = RecordingStudioMcp::UsageDailyMetric.find_by!(metric_date: day, method_name: "tools/call", subject_name: "list")
    assert_equal 2, row.call_count
    assert_equal 1, row.failed_count
    assert_equal 0, row.rate_limited_count
    limited = RecordingStudioMcp::UsageDailyMetric.find_by!(metric_date: day, method_name: "tools/call", subject_name: "show")
    assert_equal 1, limited.call_count
    assert_equal 1, limited.failed_count
    assert_equal 1, limited.rate_limited_count
  end

  test "usage table failed filter keeps failed calls" do
    RecordingStudioMcp::UsageLog.delete_all
    RecordingStudioMcp::UsageLog.create!(
      occurred_at: Time.zone.now,
      method_name: "ping",
      subject_name: "",
      status_code: 200,
      duration_ms: 2,
      rate_limited: false,
      failed: false
    )
    RecordingStudioMcp::UsageLog.create!(
      occurred_at: Time.zone.now,
      method_name: "tools/call",
      subject_name: "show",
      status_code: 500,
      duration_ms: 9,
      rate_limited: false,
      failed: true
    )

    sign_in @user
    switch_to_root!(@admin_root_recording)
    get "/admin/screens/mcp_usage/table", params: { failed: "true", method: "tools/call" }

    assert_response :success
    assert_includes response.body, "show"
    refute_includes response.body, ">ping<"
  end

  private


  def json_headers(extra = {})
    { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(extra)
  end

  def issue_token
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      role: "view",
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
