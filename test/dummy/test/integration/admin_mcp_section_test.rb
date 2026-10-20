# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminMcpSectionTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    user = create_user
    _admin_root, root_recording = create_admin_root_recording
    Current.actor = user
    grant_or_bootstrap_access!(recording: root_recording, actor: user, role: :admin)
    sign_in user
    switch_to_root!(root_recording)
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "mcp section charts the last 4 weeks and links to the usage screen" do
    get "/admin/sections/mcp"

    assert_response :success
    assert_includes response.body, "MCP admin"
    assert_includes response.body, "Ops MCP"
    assert_includes response.body, "/recording_studio_mcp/apis/operations"
    assert_includes response.body, "/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations"
    assert_includes response.body, "ChatGPT"
    assert_includes response.body, "Grok Bot"
    assert_match(/api_key:\s*&quot;operations&quot;|api_key:\s*"operations"/, response.body)
    assert_includes response.body, "Failing subscriptions"
    assert_includes response.body, "widget_view_variant=compact"
    failing_at = response.body.index("mcp.failing_subscriptions")
    ops_at = response.body.index("mcp.ops_connection")
    failed_at = response.body.index("mcp.failed_by_tool")
    assert_operator failing_at, :<, ops_at
    assert_operator ops_at, :<, failed_at
    assert_includes response.body, "Failed tools"
    assert_includes response.body, "Usage"
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "Calls from the last 4 weeks."
    assert_includes response.body, "Still listening, but the last callback bounced."
    assert_includes response.body, "Tool calls that failed, from daily totals."
    assert_includes response.body, "Registered apps"
    refute_includes response.body, "None yet"
    refute_includes response.body, "Calls from the last 7 days."
    refute_includes response.body, "What this server can do."
    refute_includes response.body, "List records"
    assert_includes response.body, "/admin/sections/oauth_apps"
    assert_includes response.body, "/admin/screens/mcp_usage"

    get "/admin/screens/mcp_usage"

    assert_response :success
    assert_includes response.body, "Every call from the last 4 weeks."
    assert_includes response.body, "/admin/screens/mcp_usage/chart"
    assert_includes response.body, "/admin/screens/mcp_usage/table"

    get "/admin/screens/mcp_usage/chart"
    assert_response :success

    get "/admin/screens/mcp_usage/table"
    assert_response :success
  end

  test "mcp section shows failing subscriptions and failed tools from metrics" do
    RecordingStudioMcp::EventSubscription.delete_all
    RecordingStudioMcp::UsageDailyMetric.delete_all
    RecordingStudioMcp::EventSubscription.create!(
      id: SecureRandom.uuid,
      owner_principal_id: "principal-#{SecureRandom.hex(4)}",
      event_name: "recording.updated",
      callback_url: "https://example.com/callback",
      callback_secret: SecureRandom.hex(16),
      status: RecordingStudioMcp::EventSubscription::ACTIVE,
      expires_at: 1.day.from_now,
      failure_count: 2
    )
    RecordingStudioMcp::EventSubscription.create!(
      id: SecureRandom.uuid,
      owner_principal_id: "principal-#{SecureRandom.hex(4)}",
      event_name: "page.commented",
      callback_url: "https://example.com/healthy",
      callback_secret: SecureRandom.hex(16),
      status: RecordingStudioMcp::EventSubscription::ACTIVE,
      expires_at: 1.day.from_now,
      failure_count: 0
    )
    RecordingStudioMcp::EventSubscription.create!(
      id: SecureRandom.uuid,
      owner_principal_id: "principal-#{SecureRandom.hex(4)}",
      event_name: "recording.updated",
      callback_url: "https://example.com/expired",
      callback_secret: SecureRandom.hex(16),
      status: RecordingStudioMcp::EventSubscription::ACTIVE,
      expires_at: 1.hour.ago,
      failure_count: 3
    )
    RecordingStudioMcp::UsageDailyMetric.create!(
      metric_date: Date.current,
      method_name: "tools/call",
      subject_name: "show",
      call_count: 3,
      failed_count: 2,
      rate_limited_count: 0
    )
    RecordingStudioMcp::UsageDailyMetric.create!(
      metric_date: Date.current,
      method_name: "tools/call",
      subject_name: "list",
      call_count: 1,
      failed_count: 1,
      rate_limited_count: 0
    )

    get "/admin/sections/mcp"

    assert_response :success
    assert_select "h3", text: "Failing subscriptions"
    assert_select "span.text-5xl", text: "1"
    assert_includes response.body, "show"
    assert_includes response.body, "list"
    assert_includes response.body, "/admin/screens/mcp_failing_subscriptions"
    assert_includes response.body, "/admin/screens/mcp_usage?failed=true&amp;method=tools%2Fcall"

    get "/admin/screens/mcp_failing_subscriptions"

    assert_response :success
    assert_includes response.body, "/admin/screens/mcp_failing_subscriptions/table"

    get "/admin/screens/mcp_failing_subscriptions/table"

    assert_response :success
    assert_includes response.body, "recording.updated"
    assert_includes response.body, "https://example.com/callback"
    refute_includes response.body, "https://example.com/healthy"
    refute_includes response.body, "https://example.com/expired"
  end

  test "mcp section is defined by the gem and the host only allowlists it" do
    source_path, = Object.const_source_location("RecordingStudioMcp::Admin::McpSection")

    assert_operator source_path, :start_with?, RecordingStudioMcp::Engine.root.to_s
    assert_operator source_path, :end_with?, "lib/recording_studio_mcp/admin.rb"

    initializer = File.read(Rails.root.join("config/initializers/recording_studio_admin.rb"))
    admin_root = File.read(Rails.root.join("app/models/admin_root.rb"))

    refute_includes initializer, "class McpSection"
    refute_includes initializer, "RecordingStudioMcp::Admin"
    assert_includes admin_root, "section :mcp"
    refute_includes admin_root, "McpSection"
    assert_includes AdminRoot.recording_studio_admin_section_keys_for(nil, nil, nil), "mcp"

    seeds = File.read(Rails.root.join("db/seeds.rb"))
    refute_includes seeds, "ChatGPT"
    refute_includes seeds, "Grok Bot"
    refute_match(/api_key\s*=\s*"operations"/, seeds)
  end

  test "admin home links mcp beside registered apps" do
    get "/admin"

    assert_response :success
    assert_includes response.body, "MCP"
    assert_includes response.body, "Registered apps"
  end
end
