# frozen_string_literal: true

require "test_helper"

class McpRecordableMetricsTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers

  setup do
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "Recordable metrics #{SecureRandom.hex(4)}")
    remember_recordable_metrics!
    register_dummy_recordable_metrics!
  end

  teardown do
    restore_recordable_metrics!
    Current.actor = nil if defined?(Current)
  end

  test "folders total returns the filtered count" do
    create_folder("Ada")
    create_folder("Bea")
    token = issue_token

    listed = mcp(token, "tools/list").dig("result", "tools")
    names = listed.map { |tool| tool.fetch("name") }
    assert_equal(
      %w[folders-created_over_time folders-total pages-total],
      names.select { |name| name.start_with?("folders-", "pages-") }
    )
    assert_operator names.index("describe"), :<, names.index("folders-created_over_time")
    assert_operator names.index("pages-total"), :<, names.index("demo_progress")

    total = listed.find { |tool| tool.fetch("name") == "folders-total" }
    assert_equal true, total.dig("annotations", "readOnlyHint")
    assert_equal false, total.dig("annotations", "destructiveHint")
    assert_equal true, total.dig("annotations", "idempotentHint")
    assert_equal "object", total.dig("inputSchema", "properties", "filter", "type")
    assert_equal "string", total.dig("inputSchema", "properties", "filter", "properties", "name", "type")
    refute total.dig("inputSchema", "properties").key?("filter[name]")

    instructions = mcp(token, "initialize", protocolVersion: "2025-06-18").dig("result", "instructions")
    assert_includes instructions, "pass list filters as a filter object of attribute names"

    filtered = call_tool(token, "folders-total", filter: { name: "Ada" })
    assert_equal false, filtered.fetch("isError")
    assert_equal 1, filtered.dig("structuredContent", "value")
    assert_equal "folders.total", filtered.dig("structuredContent", "metric")
    assert_equal 1, JSON.parse(filtered.dig("content", 0, "text")).fetch("value")

    unfiltered = call_tool(token, "folders-total")
    assert_equal false, unfiltered.fetch("isError")
    assert_equal 2, unfiltered.dig("structuredContent", "value")
  end

  test "denied view matches the api denial" do
    token = client_credentials_token
    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "public"
    )
    assert grant.success?, grant.error

    RecordingStudio::Access.where(id: grant.value.access_recording.recordable_id).update_all(role: "guest")
    ActiveRecord::Base.connection.clear_query_cache

    denied = call_tool(token, "folders-total")

    assert_equal true, denied.fetch("isError")
    assert_equal(
      "API access grant is not authorized for this capability",
      denied.dig("content", 0, "text")
    )
  end

  private

  def remember_recordable_metrics!
    registry = RecordingStudioApi.configuration.fetch_api(:public).recordable_registry
    @recordable_store = registry.instance_variable_get(:@registrations)
    @saved_recordables = @recordable_store.slice("Folder", "Page")
    metrics = RecordingStudioMetrics.registry
    @metrics_registry = metrics
    @saved_metrics = metrics.instance_variable_get(:@metrics).dup
    @saved_metric_resources = metrics.instance_variable_get(:@resources).dup
  end

  def restore_recordable_metrics!
    return unless @recordable_store

    @saved_recordables.each { |type, registration| @recordable_store[type] = registration }
    @metrics_registry.instance_variable_set(:@metrics, @saved_metrics)
    @metrics_registry.instance_variable_set(:@resources, @saved_metric_resources)
  end

  def register_dummy_recordable_metrics!
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      metrics: %w[folders.total folders.created_over_time]
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      metrics: %w[pages.total]
    )
    RecordingStudioMetrics.register(:folders, model: ::Folder, blast_radius: :root) do
      count :total, title: "Folders", description: "How many folders are in this scope."
      timeseries :created_over_time,
                 title: "Created over time",
                 description: "Folders created in the window.",
                 field: :created_at,
                 intervals: %i[day week],
                 group_by: %i[name]
    end
    RecordingStudioMetrics.register(:pages, model: ::Page, blast_radius: :root) do
      count :total, title: "Pages", description: "How many pages are in this scope."
    end
  end

  def create_folder(name)
    Current.actor = @user
    RecordingStudio.record!(
      action: "created",
      recordable: Folder.create!(name: name),
      root_recording: @root_recording,
      parent_recording: @root_recording
    ).recording
  end

  def call_tool(token, name, **arguments)
    mcp(token, "tools/call", name: name, arguments: arguments).fetch("result")
  end

  def mcp(token, method, **params)
    post "/recording_studio_mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "Authorization" => "Bearer #{token}"
         }
    assert_response :success, response.body
    response.parsed_body
  end

  def client_credentials_token
    provisioned = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: @root_recording,
      manager_actor: @user,
      role: "admin",
      name: "Metric denial #{SecureRandom.hex(4)}"
    )
    assert provisioned.success?, provisioned.error

    credential = provisioned.value.fetch(:credential)
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: credential.oauth_client_id,
      client_secret: provisioned.value.fetch(:token)
    )
    assert issued.success?, issued.error

    issued.value.fetch(:access_token)
  end

  def issue_token
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
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
