# frozen_string_literal: true

require "test_helper"

class McpMetricsApiTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers

  OPERATIONS_ROOT = "/recording_studio_api/apis/operations/v1"
  PUBLIC_ROOT = "/recording_studio_api/api/v1"

  setup do
    @staff = create_user
    Current.actor = @staff
    _admin_root, @admin_recording = create_admin_root_recording
    @admin_root_access = grant_or_bootstrap_access!(
      recording: @admin_recording,
      actor: @staff,
      role: :admin
    )
    @workspace_root, @workspace_access = create_access_recording_for(user: @staff)

    RecordingStudioMcp::UsageLog.delete_all
    @day_one = Date.current - 2
    @day_two = Date.current - 1
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
    over_time = execute(
      "mcp_calls.over_time",
      interval: :day,
      start_at: @day_one.in_time_zone("UTC").beginning_of_day,
      end_at: (@day_two + 1).in_time_zone("UTC").beginning_of_day
    )
    over_time_values = over_time.data.to_h { |row| [row[:date], row[:value]] }
    assert_equal 12, over_time_values[@day_one.iso8601]
    assert_equal 7, over_time_values[@day_two.iso8601]

    failed = execute(
      "mcp_calls.failed_over_time",
      interval: :day,
      start_at: @day_one.in_time_zone("UTC").beginning_of_day,
      end_at: (@day_two + 1).in_time_zone("UTC").beginning_of_day
    )
    failed_values = failed.data.to_h { |row| [row[:date], row[:value]] }
    assert_equal 2, failed_values[@day_one.iso8601]
    assert_equal 1, failed_values[@day_two.iso8601]

    tools = execute("mcp_calls.by_tool").data.to_h { |row| [row[:key].to_s, row[:value]] }
    assert_equal 10, tools["list"]
    assert_equal 3, tools["show"]
    refute_includes tools.keys, "initialize"

    methods = execute("mcp_calls.by_method").data.to_h { |row| [row[:key].to_s, row[:value]] }
    assert_equal 13, methods["tools/call"]
    assert_equal 6, methods["initialize"]

    assert_equal 4, execute("mcp_calls.rate_limited").value

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/over_time",
        params: { interval: "day" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    over_time_http = timeseries_counts(response.parsed_body)
    assert_equal 12, over_time_http[@day_one.iso8601]
    assert_equal 7, over_time_http[@day_two.iso8601]

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/failed_over_time",
        params: { interval: "day" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    failed_http = timeseries_counts(response.parsed_body)
    assert_equal 2, failed_http[@day_one.iso8601]
    assert_equal 1, failed_http[@day_two.iso8601]

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/by_tool",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    tools_http = breakdown_counts(response.parsed_body)
    assert_equal 10, tools_http["list"]
    assert_equal 3, tools_http["show"]
    refute_includes tools_http.keys, "initialize"

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/by_method",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    methods_http = breakdown_counts(response.parsed_body)
    assert_equal 13, methods_http["tools/call"]
    assert_equal 6, methods_http["initialize"]

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    assert_equal 4, response.parsed_body.fetch("value")
  end

  test "failed_by_tool sums failed tools/call rows per tool" do
    failed = execute("mcp_calls.failed_by_tool").data.to_h { |row| [row[:key].to_s, row[:value]] }
    assert_equal 1, failed["list"]
    assert_equal 2, failed["show"]
    refute_includes failed.keys, ""

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/failed_by_tool",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    http = breakdown_counts(response.parsed_body)
    assert_equal 1, http["list"]
    assert_equal 2, http["show"]
    refute_includes http.keys, ""
  end

  test "mcp_subscriptions.failing counts active unexpired subscriptions with failures" do
    RecordingStudioMcp::EventSubscription.delete_all
    create_subscription(failure_count: 2)
    create_subscription(failure_count: 1)
    create_subscription(failure_count: 0)
    create_subscription(failure_count: 5, status: RecordingStudioMcp::EventSubscription::INACTIVE)
    create_subscription(failure_count: 3, expires_at: 1.hour.ago)

    assert_equal 2, execute("mcp_subscriptions.failing").value

    get "#{OPERATIONS_ROOT}/metrics/mcp_subscriptions/failing", headers: auth(@staff_operations_token), as: :json
    assert_response :success
    assert_equal 2, response.parsed_body.fetch("value")

    counted = call_tool("mcp_subscriptions-failing")
    assert_equal false, counted.fetch("isError"), counted.dig("content", 0, "text")
    assert_equal 2, counted.dig("structuredContent", "value")
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
      mcp_calls.failed_by_tool
      mcp_subscriptions.failing
    ].each { |identifier| assert_includes identifiers, identifier }
  end

  test "a raising metric authorize hook stays off tools/list and keeps sibling metrics" do
    secret = "secret-token sk-probe"
    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)
    registry = RecordingStudioMetrics.registry
    saved_metrics = registry.instance_variable_get(:@metrics).dup
    saved_resources = registry.instance_variable_get(:@resources).dup
    RecordingStudioMetrics.register(
      :probes,
      model: RecordingStudioMcp::UsageLog,
      blast_radius: :site,
      api_authorize: ->(_context) { raise secret }
    ) do
      count :total, title: "Probes", expose: { api: [:operations] }
    end

    post named_mcp_path("operations"),
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "Authorization" => "Bearer #{@staff_operations_token}"
         }

    assert_response :success
    refute_includes response.body, "-32603"
    refute_includes response.body, secret
    names = response.parsed_body.dig("result", "tools").map { |tool| tool.fetch("name") }
    assert_includes names, "mcp_calls-rate_limited"
    refute_includes names, "probes-total"
    assert_includes warnings.string, "WARN --"
    assert_includes warnings.string, "skipped metric probes"
    refute_includes warnings.string, secret
  ensure
    Rails.logger = previous if previous
    if defined?(registry) && registry
      registry.instance_variable_set(:@metrics, saved_metrics)
      registry.instance_variable_set(:@resources, saved_resources)
    end
  end

  test "operations MCP lists one tool per mcp_calls metric and keeps the metrics endpoints" do
    tools = mcp(@staff_operations_token, "tools/list").dig("result", "tools").index_by { |tool| tool.fetch("name") }

    assert_includes tools.keys, "operations_metrics_index"
    assert_includes tools.keys, "operations_metrics_show"
    %w[
      mcp_calls-over_time
      mcp_calls-failed_over_time
      mcp_calls-by_tool
      mcp_calls-failed_by_tool
      mcp_calls-by_method
      mcp_calls-rate_limited
      mcp_subscriptions-failing
    ].each { |name| assert_includes tools.keys, name }

    over_time = tools.fetch("mcp_calls-over_time").fetch("inputSchema")
    assert_equal false, over_time.fetch("additionalProperties")
    assert_equal "Same as start.", over_time.dig("properties", "start", "description")
    assert_equal "Same as end.", over_time.dig("properties", "end", "description")
    assert_equal %w[day week month year], over_time.dig("properties", "interval", "enum")
    refute over_time.fetch("properties").key?("group_by")

    rate_limited = tools.fetch("mcp_calls-rate_limited").fetch("inputSchema")
    refute rate_limited.fetch("properties").key?("from")
    refute tools.fetch("mcp_calls-by_tool").fetch("inputSchema").fetch("properties").key?("from")
    refute tools.fetch("mcp_calls-failed_by_tool").fetch("inputSchema").fetch("properties").key?("from")
    refute tools.fetch("mcp_subscriptions-failing").fetch("inputSchema").fetch("properties").key?("from")

    counted = call_tool("mcp_calls-rate_limited")
    assert_equal false, counted.fetch("isError"), counted.dig("content", 0, "text")
    assert_equal 4, counted.dig("structuredContent", "value")

    series = call_tool(
      "mcp_calls-over_time",
      from: @day_one.in_time_zone("UTC").beginning_of_day.iso8601,
      to: (@day_two + 1).in_time_zone("UTC").beginning_of_day.iso8601,
      interval: "day"
    )
    assert_equal false, series.fetch("isError"), series.dig("content", 0, "text")
    values = series.dig("structuredContent", "data").to_h { |row| [row.fetch("date"), row.fetch("value")] }
    assert_equal 12, values[@day_one.iso8601]
    assert_equal 7, values[@day_two.iso8601]

    unknown = call_tool("mcp_calls-rate_limited", nope: "1")
    assert_equal true, unknown.fetch("isError")
    assert_equal "Unknown argument nope", unknown.dig("content", 0, "text")

    failed_by_tool = call_tool("mcp_calls-failed_by_tool")
    assert_equal false, failed_by_tool.fetch("isError"), failed_by_tool.dig("content", 0, "text")
    failed_values = failed_by_tool.dig("structuredContent", "data").to_h do |row|
      [row.fetch("key"), row.fetch("value")]
    end
    assert_equal 1, failed_values["list"]
    assert_equal 2, failed_values["show"]
    refute_includes failed_values.keys, ""
  end

  test "a workspace operations token does not see mcp_calls tools" do
    names = mcp(@workspace_operations_token, "tools/list").dig("result", "tools").map { |tool| tool.fetch("name") }

    refute_includes names, "mcp_calls-rate_limited"
    refute_includes names, "mcp_calls-failed_by_tool"
    refute_includes names, "mcp_subscriptions-failing"
    assert_includes names, "operations_metrics_index"
    denied = mcp(
      @workspace_operations_token, "tools/call", name: "mcp_calls-rate_limited", arguments: {}
    ).fetch("result")
    assert_equal true, denied.fetch("isError")
    assert_includes denied.dig("content", 0, "text"), "Unknown tool mcp_calls-rate_limited"

    %w[mcp_calls-failed_by_tool mcp_subscriptions-failing].each do |name|
      hidden = mcp(@workspace_operations_token, "tools/call", name: name, arguments: {}).fetch("result")
      assert_equal true, hidden.fetch("isError")
      assert_includes hidden.dig("content", 0, "text"), "Unknown tool #{name}"
    end
  end

  test "catalog metric resources allowlist hides mcp_calls tools" do
    previous = RecordingStudioMcp.configuration.catalog_metric_resources
    RecordingStudioMcp.configuration.catalog_metric_resources = ["other"]
    names = mcp(@staff_operations_token, "tools/list").dig("result", "tools").map { |tool| tool.fetch("name") }

    refute_includes names, "mcp_calls-over_time"
    assert_includes names, "operations_metrics_show"
  ensure
    RecordingStudioMcp.configuration.catalog_metric_resources = previous
  end

  test "recordable metric tools do not replace operations metrics" do
    names = mcp(@staff_operations_token, "tools/list").dig("result", "tools").map { |tool| tool.fetch("name") }

    assert_includes names, "operations_metrics_index"
    assert_includes names, "operations_metrics_show"
    refute_includes names, "folders-total"
    refute_includes names, "pages-total"
  end

  test "operations MCP metrics tools advertise Metrics query params" do
    tools = mcp(@staff_operations_token, "tools/list").dig("result", "tools").index_by { |tool| tool["name"] }

    show = tools.fetch("operations_metrics_show").fetch("inputSchema")
    %w[from to start end interval group_by timezone filters].each do |name|
      assert show.fetch("properties").key?(name), "missing #{name}"
    end
    assert_equal %w[hour day week month year], show.dig("properties", "interval", "enum")
    assert_equal "date-time", show.dig("properties", "from", "format")
    assert_includes show.dig("properties", "group_by", "description"), "other"
    assert_equal %w[resource name], show.fetch("required")

    index = tools.fetch("operations_metrics_index").fetch("inputSchema")
    assert_equal "string", index.dig("properties", "filters", "properties", "resource", "type")
  end

  test "operations MCP metrics show passes from to and interval through" do
    result = call_tool(
      "operations_metrics_show",
      resource: "mcp_calls",
      name: "over_time",
      interval: "day",
      from: @day_two.in_time_zone("UTC").beginning_of_day.iso8601,
      to: (@day_two + 1).in_time_zone("UTC").beginning_of_day.iso8601,
      timezone: "UTC"
    )

    refute result.fetch("isError"), result.inspect
    values = timeseries_counts(result.fetch("structuredContent"))
    assert_equal({ @day_two.iso8601 => 7 }, values)
  end

  test "operations MCP metrics show surfaces Metrics errors as tool errors" do
    # API 0.8 folds `from` into `start`; an explicit `start` wins instead of conflicting.
    precedence = call_tool(
      "operations_metrics_show",
      resource: "mcp_calls",
      name: "over_time",
      start: @day_one.iso8601,
      from: @day_two.iso8601
    )
    refute precedence.fetch("isError"), precedence.inspect

    group = call_tool("operations_metrics_show", resource: "mcp_calls", name: "by_tool", group_by: "nope")
    assert group.fetch("isError")
    refute_empty group.dig("content", 0, "text")
  end

  test "operations MCP metrics index passes the resource filter through" do
    result = call_tool("operations_metrics_index", filters: { resource: "mcp_calls" })

    refute result.fetch("isError"), result.inspect
    resources = result.dig("structuredContent", "metrics").map { |row| row.fetch("resource").to_s }.uniq
    assert_equal ["mcp_calls"], resources

    unknown = call_tool("operations_metrics_index", filters: { nope: "x" })
    assert unknown.fetch("isError")
    assert_includes unknown.dig("content", 0, "text"), "Unknown filters: nope"
  end

  test "non-admin operations token is denied MCP metrics" do
    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/failed_by_tool",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics/mcp_subscriptions/failing",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@workspace_operations_token), as: :json
    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    refute_includes identifiers, "mcp_calls.rate_limited"
    refute_includes identifiers, "mcp_calls.failed_by_tool"
    refute_includes identifiers, "mcp_subscriptions.failing"
  end

  test "public API token is denied operations MCP metrics" do
    get "#{OPERATIONS_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@public_token),
        as: :json
    assert_includes [401, 403], response.status

    get "#{PUBLIC_ROOT}/metrics/mcp_calls/rate_limited",
        headers: auth(@public_token),
        as: :json
    assert_includes [404, 401, 403], response.status
  end

  private

  def seed_daily_metrics!
    create_daily_metric(
      metric_date: @day_one,
      method_name: "tools/call",
      subject_name: "list",
      call_count: 8,
      failed_count: 1,
      rate_limited_count: 1
    )
    create_daily_metric(
      metric_date: @day_one,
      method_name: "tools/call",
      subject_name: "show",
      call_count: 2,
      failed_count: 1,
      rate_limited_count: 2
    )
    create_daily_metric(
      metric_date: @day_one,
      method_name: "initialize",
      subject_name: "",
      call_count: 2,
      failed_count: 0,
      rate_limited_count: 0
    )
    create_daily_metric(
      metric_date: @day_two,
      method_name: "tools/call",
      subject_name: "list",
      call_count: 2,
      failed_count: 0,
      rate_limited_count: 0
    )
    create_daily_metric(
      metric_date: @day_two,
      method_name: "tools/call",
      subject_name: "show",
      call_count: 1,
      failed_count: 1,
      rate_limited_count: 1
    )
    create_daily_metric(
      metric_date: @day_two,
      method_name: "initialize",
      subject_name: "",
      call_count: 4,
      failed_count: 0,
      rate_limited_count: 0
    )
  end

  def create_subscription(
    failure_count:,
    status: RecordingStudioMcp::EventSubscription::ACTIVE,
    expires_at: 1.day.from_now
  )
    RecordingStudioMcp::EventSubscription.create!(
      id: SecureRandom.uuid,
      owner_principal_id: "principal-#{SecureRandom.hex(4)}",
      event_name: "recording.updated",
      callback_url: "https://example.com/callback",
      callback_secret: SecureRandom.hex(16),
      status: status,
      expires_at: expires_at,
      failure_count: failure_count
    )
  end

  def create_daily_metric(metric_date:, method_name:, subject_name:, call_count:, failed_count:, rate_limited_count:)
    stamp = metric_date.in_time_zone("UTC").change(hour: 12)
    call_count.times do |index|
      RecordingStudioMcp::UsageLog.create!(
        occurred_at: stamp,
        method_name: method_name,
        subject_name: subject_name,
        status_code: index < failed_count ? 500 : 200,
        duration_ms: 1,
        failed: index < failed_count,
        rate_limited: index < rate_limited_count
      )
    end
  end

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: RecordingStudioMetrics::Context.new(
        actor: @staff,
        scope: :site,
        site_authorized: true,
        timezone: "UTC"
      ),
      **params
    )
  end

  def breakdown_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }
  end

  def timeseries_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("date").to_s, row.fetch("value")] }
  end

  def call_tool(name, **arguments)
    mcp(@staff_operations_token, "tools/call", name: name, arguments: arguments).fetch("result")
  end

  def mcp(token, method, **params)
    post named_mcp_path("operations"),
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json",
                    "Authorization" => "Bearer #{token}" }
    assert_response :success, response.body
    response.parsed_body
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
