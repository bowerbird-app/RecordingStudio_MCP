# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpDocsTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  CDN_NEEDLES = %w[
    cdn.redocly.com
    cdn.redoc.ly
    unpkg.com
    jsdelivr
    otel.cloud.redocly.com
  ].freeze
  DOCS_ASSETS = %w[redoc.js logo-mini.svg logo-mini-full.svg].freeze

  setup do
    @previous_enabled = RecordingStudioMcp.configuration.documentation_enabled
    @previous_access = RecordingStudioMcp.configuration.documentation_access
    @previous_layout = RecordingStudioMcp.configuration.documentation_layout_name
    RecordingStudioMcp.configuration.documentation_enabled = true
    RecordingStudioMcp.configuration.documentation_access = :authenticated
    RecordingStudioMcp.configuration.documentation_layout_name = "recording_studio/default_layout"
  end

  teardown do
    RecordingStudioMcp.configuration.documentation_enabled = @previous_enabled
    RecordingStudioMcp.configuration.documentation_access = @previous_access
    RecordingStudioMcp.configuration.documentation_layout_name = @previous_layout
    Current.actor = nil if defined?(Current)
  end

  test "public docs render redoc pointed at the live spec with telemetry off" do
    sign_in_user

    get public_api_mcp_docs_path

    assert_response :success
    assert_includes response.body, 'data-recording-studio-mcp-docs="public"'
    assert_includes response.body, "Public MCP"
    assert_includes response.body, 'disable-telemetry="true"'
    assert_includes response.body, "disableTelemetry: true"
    assert_includes response.body, "#{public_api_mcp_docs_path}/openapi.json"
    assert_includes response.body, "#{public_api_mcp_docs_path}/redoc.js"
    assert_select %(a[href="#{public_api_mcp_docs_fullscreen_path}"]), text: "Full width"
    assert_select '[data-recording-studio-default-layout]'
    assert_includes response.body, "max-w-6xl"
    assert_includes response.body, "Live tools for this API."
    fragment = response.body[%r{<div[^>]*data-recording-studio-mcp-docs.*?</script>\s*</div>}m]
    assert fragment.present?
    CDN_NEEDLES.each { |needle| refute_includes fragment, needle }
  end

  test "docs without javascript list tool names and the openapi document" do
    sign_in_user

    get public_api_mcp_docs_path

    assert_response :success
    assert_docs_tool_fallback response.body, "#{public_api_mcp_docs_path}/openapi.json"

    get public_api_mcp_docs_fullscreen_path

    assert_response :success
    assert_docs_tool_fallback response.body, "#{public_api_mcp_docs_path}/openapi.json"
  end

  test "fullscreen docs render redoc with no host layout and the same gate" do
    sign_in_user

    get public_api_mcp_docs_fullscreen_path

    assert_response :success
    assert_match(/\A\s*<!doctype html>/i, response.body)
    assert_includes response.body, 'data-recording-studio-mcp-docs="public"'
    assert_includes response.body, "#{public_api_mcp_docs_path}/openapi.json"
    assert_includes response.body, "#{public_api_mcp_docs_path}/redoc.js"
    refute_includes response.body, "#{public_api_mcp_docs_fullscreen_path}/openapi.json"
    refute_includes response.body, "#{public_api_mcp_docs_fullscreen_path}/redoc.js"
    assert_includes response.body, 'disable-telemetry="true"'
    refute_includes response.body, "Full width"
    refute_includes response.body, "max-w-6xl"
    refute_includes response.body, 'data-recording-studio-default-layout'
  end

  test "public spec lists registered tools types writable fields and capability actions" do
    sign_in_user

    get public_api_mcp_docs_openapi_path

    assert_response :success
    spec = JSON.parse(response.body)
    names = spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
    schemas = spec.dig("components", "schemas")

    assert_equal "3.1.0", spec["openapi"]
    assert_includes names, "list"
    assert_includes names, "describe"
    assert_includes names, "ping"
    assert_includes names, "create"
    ping_workspace = RecordingStudioMcp.tool_name("Workspace", :ping)
    assert_includes names, ping_workspace
    assert_docs_match_tools_list names, path: "/recording_studio_mcp", api: "public"
    assert_equal ["TypeName"], schemas.keys
    refute_includes schemas.keys, "Workspace"
    refute_includes schemas.keys, "Folder"
    refute_includes schemas.keys, "Page"
    refute spec.dig("x-mcp").key?("resources")
    refute spec.dig("x-mcp").key?("resourceTemplates")
    description = spec.dig("info", "description")
    refute_empty description
    assert_includes description, "## Sign in"
    assert_includes description, "## Walk your records"
    refute_includes description, "view-only connection"
    assert_equal spec.dig("x-mcp", "instructions"), description
    tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
    assert_equal ["Overview"], tools.fetch("list")["tags"]
    assert_equal ["Overview"], tools.fetch("ping")["tags"]
    assert_equal ["Overview"], tools.fetch("create")["tags"]
    assert_equal ["Workspace"], tools.fetch(ping_workspace)["tags"]
    %w[grant_access list_access revoke_access update_access].each do |action|
      refute_includes names, "Workspace--#{action}"
    end
    assert tools.fetch("list").key?("outputSchema")
    refute tools.fetch("list").key?("x-mcp-docs-only")
    intro = spec.fetch("tags").find { |tag| tag["name"] == "Workspace" }.fetch("description")
    assert_equal 1, intro.scan("Tool: list with type `Workspace`").size
    assert_includes intro, "Tool: list with type `Workspace`\n"
    refute_includes intro, "Tool: list with type `Workspace` and parent_id"
    assert_includes intro, "Tool: show with type `Workspace` and id"
    assert_includes intro, "Tool: create with type `Workspace`, parent_id, writable fields at the top level, " \
                            "and optional idempotency_key"
    assert_includes intro, "Tool: update with type `Workspace`, id, and writable fields"
    refute_includes intro, "Tool: delete"
    assert_includes intro, "Tool: capability_action with type `Workspace`."
    assert_includes intro, "Capability actions:"
    %w[ping grant_access list_access revoke_access update_access].each do |action|
      assert_includes intro, "- #{action}"
    end
    tag_names = spec.fetch("tags").map { |tag| tag["name"] }
    refute_includes tag_names, "Folder"
    refute_includes tag_names, "Page"
    refute tools.key?("Folder--list")
    refute tools.key?("Workspace--list")
    refute tools.key?("Workspace--delete")
    assert_equal "Overview", tag_names.first
    refute_includes tag_names, "Core"
    refute_includes tag_names, "Tools"
    assert_includes tag_names, "Workspace"
    refute_includes tag_names, "Endpoints"
    refute_includes tag_names, "Tools"
    refute_includes tag_names, "Resources"
    refute_includes tag_names, "Types"
    assert_equal "Other tools", tag_names.last if tag_names.include?("Other tools")
    assert_equal tag_names.uniq, tag_names
    refute spec.key?("x-tagGroups")
  end

  test "operations spec is the operations catalog not dummy tree types" do
    sign_in_user

    get operations_api_mcp_docs_path
    assert_response :success
    assert_includes response.body, 'data-recording-studio-mcp-docs="operations"'

    get operations_api_mcp_docs_openapi_path
    assert_response :success
    spec = JSON.parse(response.body)
    names = spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
    schemas = spec.dig("components", "schemas") || {}

    assert_includes names, "ops_ping"
    assert_docs_match_tools_list names, path: named_mcp_path("operations"), api: "operations"
    refute_includes schemas.keys, "Workspace"
    refute_includes schemas.keys, "Folder"
    assert_includes schemas.keys, "TypeName"
    description = spec.dig("info", "description")
    refute_includes description, "Call describe"
    refute_includes description, "## Walk your records"
    assert_includes description, "## If you only see named route tools"
    assert_includes description, "## Sign in"
    ping = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "ops_ping" }
    assert_equal ["Other tools"], ping["tags"]
    tag_names = spec.fetch("tags").map { |tag| tag["name"] }
    assert_equal tag_names.uniq, tag_names
    refute spec.key?("x-tagGroups")
  end

  test "redoc bundle rewrites logo urls to the gated mount" do
    sign_in_user
    logo = "#{public_api_mcp_docs_path}/logo-mini-full.svg"
    logo_mini = "#{public_api_mcp_docs_path}/logo-mini.svg"

    get "#{public_api_mcp_docs_path}/redoc.js"

    assert_response :success
    assert_includes response.media_type, "javascript"
    assert_includes response.body, logo
    assert_includes response.body, logo_mini
    refute_includes response.body, RecordingStudioMcp::Redoc::LOGO_MINI_FULL_TOKEN
    refute_includes response.body, RecordingStudioMcp::Redoc::LOGO_MINI_TOKEN
    CDN_NEEDLES.each { |needle| refute_includes response.body, needle }

    get logo
    assert_response :success
    assert_includes response.media_type, "svg"

    get logo_mini
    assert_response :success
    assert_includes response.media_type, "svg"
  end

  test "host gate callable allowing access returns 200" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_access = lambda do |controller:, actor:, api:|
      controller.present? && actor.present? && api.present?
    end

    assert_docs_surfaces :success
  end

  test "public access with no actor returns 200" do
    RecordingStudioMcp.configuration.documentation_access = :public

    assert_docs_surfaces :success
    get public_api_mcp_docs_openapi_path
    spec = JSON.parse(response.body)
    assert_includes spec.dig("components", "schemas").keys, "TypeName"
    refute_includes spec.dig("components", "schemas").keys, "Workspace"
  end

  test "host gate denies signed-in visitors with 403" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_access = lambda do |controller:, actor:, api:|
      controller && actor && api
      false
    end

    assert_docs_surfaces :forbidden
  end

  test "host gate denies signed-out visitors with 401" do
    RecordingStudioMcp.configuration.documentation_access = lambda do |**|
      false
    end

    assert_docs_surfaces :unauthorized
  end

  test "authenticated docs require a signed-in actor" do
    assert_docs_surfaces :unauthorized
  end

  test "disabled documentation is not exposed" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_enabled = false

    assert_docs_surfaces :not_found
  end

  private

  def sign_in_user
    user = create_user
    Current.actor = user
    sign_in user
    user
  end

  def assert_docs_tool_fallback(body, spec_path)
    fallback = body[%r{<noscript>(.*?)</noscript>}m]
    assert fallback
    assert_includes fallback, spec_path
    assert_includes fallback, "## Sign in"
    assert_includes fallback, "ping checks the connection."
    assert_includes fallback, ">Overview<"
    assert_includes fallback, ">list<"
    assert_includes fallback, ">create<"
    assert_includes fallback, ">ping<"
    assert_includes fallback, ">#{RecordingStudioMcp.tool_name("Workspace", :ping)}<"
    refute_includes fallback, ">Core<"
    refute_includes fallback, ">Folder<"
    refute_includes fallback, ">Page<"
    assert_operator fallback.index(">Overview<"), :<, fallback.index(">Workspace<")
    other = fallback.index(">Other tools<")
    assert_operator fallback.index(">Overview<"), :<, other if other
  end

  def assert_docs_match_tools_list(docs_names, path:, api:)
    token = mcp_docs_list_token(api)
    post path,
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "Authorization" => "Bearer #{token}"
         }

    assert_response :success, response.body
    listed = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }
    assert_equal listed.sort, docs_names.sort
  end

  def mcp_docs_list_token(api)
    previous = Current.actor if defined?(Current)
    user = create_user
    Current.actor = user
    client, = create_oauth_client(name: "Docs list #{SecureRandom.hex(4)}", api: api)
    access = if api.to_s == "operations"
               _admin_root, recording = create_admin_root_recording
               grant_or_bootstrap_access!(recording: recording, actor: user, role: :admin)
             else
               _root, access_recording = create_access_recording_for(user: user, role: :admin)
               access_recording
             end
    pkce = pkce_pair
    approved = approve_delegated_oauth(
      oauth_client: client,
      user: user,
      access_recording: access,
      role: "edit",
      pkce: pkce
    )
    token_url = api.to_s == "public" ? "/recording_studio_api/oauth/token" : named_api_token_path(api)
    post token_url, params: {
      grant_type: "authorization_code",
      client_id: client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: pkce.fetch(:verifier)
    }
    assert_response :success, response.body
    JSON.parse(response.body).fetch("access_token")
  ensure
    Current.actor = previous if defined?(Current)
  end

  def assert_docs_surfaces(status)
    get public_api_mcp_docs_path
    assert_response status
    get public_api_mcp_docs_fullscreen_path
    assert_response status
    get public_api_mcp_docs_openapi_path
    assert_response status
    DOCS_ASSETS.each do |asset|
      get "#{public_api_mcp_docs_path}/#{asset}"
      assert_response status
    end
  end
end
