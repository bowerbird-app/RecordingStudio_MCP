# frozen_string_literal: true

require "test_helper"

class McpMetricsApiTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers

  OPERATIONS_ROOT = "/recording_studio_api/apis/operations/v1"
  PUBLIC_ROOT = "/recording_studio_api/api/v1"

  setup do
    @staff = create_user
    @outsider = create_user(email: "metrics-outsider-#{SecureRandom.hex(4)}@example.com")
    Current.actor = @staff
    _admin_root, @admin_recording = create_admin_root_recording
    @admin_root_access = grant_or_bootstrap_access!(
      recording: @admin_recording,
      actor: @staff,
      role: :admin
    )
    @workspace_root, @workspace_access = create_access_recording_for(user: @staff)

    RecordingStudioMcp::UsageDailyMetric.delete_all
    seed_daily_metrics!

    @ops_client, = create_oauth_client(name: "Ops metrics #{SecureRandom.hex(4)}", api: "operations")
    @workspace_ops_client, = create_oauth_client(name: "Workspace ops metrics #{SecureRandom.hex(4)}", api: "operations")
    @public_client, = create_oauth_client(name: "Public metrics #{SecureRandom.hex(4)}")
    @pkce = pkce_pair

    @staff_operations_token = issue_token(client: @ops_client, access_recording: @admin_root_access, api: "operations")
    @workspace_operations_token = issue_token(
      client: @workspace_ops_client,
      access_recording: @workspace_access,
      api: "operations"
    )
    @public_token = issue_token(client: @public_client, access_recording: @workspace_access)
    Current.actor = nil
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "staff operations token reads seeded MCP usage metrics" do
    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/over_time",
        params: { interval: "day", start: "2026-04-01", end: "2026-04-04" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    over_time = timeseries_counts(response.parsed_body)
    assert_equal 12, over_time["2026-04-01"]
    assert_equal 7, over_time["2026-04-02"]

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/failed_over_time",
        params: { interval: "day", start: "2026-04-01", end: "2026-04-04" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    failed = timeseries_counts(response.parsed_body)
    assert_equal 2, failed["2026-04-01"]
    assert_equal 1, failed["2026-04-02"]

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/by_tool",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    tools = breakdown_counts(response.parsed_body)
    assert_equal 10, tools["list"]
    assert_equal 3, tools["show"]
    refute_includes tools.keys, "initialize"

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/by_method",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    methods = breakdown_counts(response.parsed_body)
    assert_equal 13, methods["tools/call"]
    assert_equal 6, methods["initialize"]

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    assert_equal 4, response.parsed_body.fetch("value")
  end

  test "metrics index lists MCP call metrics" do
    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@staff_operations_token), as: :json

    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    %w[
      mcp_calls.over_time
      mcp_calls.failed_over_time
      mcp_calls.by_tool
      mcp_calls.by_method
      mcp_calls.rate_limited
    ].each { |identifier| assert_includes identifiers, identifier }
  end

  test "non-admin operations token is denied MCP metrics" do
    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@workspace_operations_token), as: :json
    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    refute_includes identifiers, "mcp_calls.rate_limited"
  end

  test "public API token is denied operations MCP metrics" do
    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{PUBLIC_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@public_token),
        as: :json
    assert_includes [404, 401, 403], response.status
  end

  private

  def seed_daily_metrics!
    create_daily_metric(
      metric_date: Date.new(2026, 4, 1),
      method_name: "tools/call",
      subject_name: "list",
      call_count: 8,
      failed_count: 1,
      rate_limited_count: 1
    )
    create_daily_metric(
      metric_date: Date.new(2026, 4, 1),
      method_name: "tools/call",
      subject_name: "show",
      call_count: 2,
      failed_count: 1,
      rate_limited_count: 2
    )
    create_daily_metric(
      metric_date: Date.new(2026, 4, 1),
      method_name: "initialize",
      subject_name: "",
      call_count: 2,
      failed_count: 0,
      rate_limited_count: 0
    )
    create_daily_metric(
      metric_date: Date.new(2026, 4, 2),
      method_name: "tools/call",
      subject_name: "list",
      call_count: 2,
      failed_count: 0,
      rate_limited_count: 0
    )
    create_daily_metric(
      metric_date: Date.new(2026, 4, 2),
      method_name: "tools/call",
      subject_name: "show",
      call_count: 1,
      failed_count: 1,
      rate_limited_count: 1
    )
    create_daily_metric(
      metric_date: Date.new(2026, 4, 2),
      method_name: "initialize",
      subject_name: "",
      call_count: 4,
      failed_count: 0,
      rate_limited_count: 0
    )
  end

  def create_daily_metric(metric_date:, method_name:, subject_name:, call_count:, failed_count:, rate_limited_count:)
    RecordingStudioMcp::UsageDailyMetric.create!(
      metric_date: metric_date,
      method_name: method_name,
      subject_name: subject_name,
      call_count: call_count,
      failed_count: failed_count,
      rate_limited_count: rate_limited_count
    )
  end

  def breakdown_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }
  end

  def timeseries_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("date").to_s, row.fetch("value")] }
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def issue_token(client:, access_recording:, api: "public")
    approved = approve_delegated_oauth(
      oauth_client: client,
      user: @staff,
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
