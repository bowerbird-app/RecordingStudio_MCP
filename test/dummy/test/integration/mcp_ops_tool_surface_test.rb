# frozen_string_literal: true

require "test_helper"

class McpOpsToolSurfaceTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers

  setup do
    @staff = create_user
    Current.actor = @staff
    _admin_root, @admin_recording = create_admin_root_recording
    @admin_root_access = grant_or_bootstrap_access!(
      recording: @admin_recording,
      actor: @staff,
      role: :admin
    )
    @ops_client, = create_oauth_client(name: "Ops surface #{SecureRandom.hex(4)}", api: "operations")
    @pkce = pkce_pair
    @staff_operations_token = issue_token(client: @ops_client, access_recording: @admin_root_access, api: "operations")
    Current.actor = nil
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "ops tools/call builds one ToolSurface and discovers the catalog once" do
    counts = { builds: 0, collects: 0, discoveries: 0, resources: [] }
    wrap_singleton(RecordingStudioMcp::ToolSurface, :for) do |original, **kwargs|
      counts[:builds] += 1
      original.call(**kwargs)
    end
    wrap_singleton(RecordingStudioMcp::MetricTools, :collect_catalog) do |original, *args, **kwargs|
      counts[:collects] += 1 if args[1]
      original.call(*args, **kwargs)
    end
    wrap_singleton(RecordingStudioMetrics::Api::DiscoveryHandler, :call) do |original, context|
      counts[:discoveries] += 1
      filters = context.params[:filters] || context.params["filters"] || {}
      counts[:resources] << (filters[:resource] || filters["resource"])
      original.call(context)
    end

    post named_mcp_path("operations"),
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: "ops_ping", arguments: {} } }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "Authorization" => "Bearer #{@staff_operations_token}"
         }

    assert_response :success, response.body
    refute response.parsed_body.dig("result", "isError")
    assert_equal 1, counts[:builds]
    assert_equal 1, counts[:collects]
    assert_operator counts[:discoveries], :>=, 1
    assert_equal counts[:resources].uniq, counts[:resources]
    assert_equal counts[:resources].size, counts[:discoveries]
  ensure
    restore_singleton_wrappers!
  end

  private

  def wrap_singleton(owner, name, &wrapper)
    @singleton_wrappers ||= []
    singleton = owner.singleton_class
    original = owner.method(name)
    aliased = :"#{name}_without_count_#{@singleton_wrappers.size}"
    singleton.alias_method aliased, name
    singleton.define_method(name) do |*args, **kwargs|
      wrapper.call(original, *args, **kwargs)
    end
    @singleton_wrappers << [singleton, name, aliased]
  end

  def restore_singleton_wrappers!
    Array(@singleton_wrappers).reverse_each do |singleton, name, aliased|
      singleton.alias_method name, aliased
      singleton.remove_method aliased
    end
    @singleton_wrappers = []
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
