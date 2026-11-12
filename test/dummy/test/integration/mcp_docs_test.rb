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
    assert_includes names, "Workspace--ping"
    assert_equal ["TypeName"], schemas.keys
    refute_includes schemas.keys, "Workspace"
    refute_includes schemas.keys, "Folder"
    refute_includes schemas.keys, "Page"
    assert_equal "recording://{id}", spec.dig("x-mcp", "resourceTemplates", 0, "uriTemplate")
    description = spec.dig("info", "description")
    refute_empty description
    assert_includes description, "## Authentication"
    assert_includes description, "## Records and parents"
    assert_includes description, "\n- "
    refute_equal description, spec.dig("x-mcp", "instructions")
    tools = spec.dig("x-mcp", "tools").index_by { |tool| tool["name"] }
    assert_equal ["Core"], tools.fetch("list")["tags"]
    assert_equal ["Endpoints"], tools.fetch("ping")["tags"]
    assert tools.fetch("list").key?("outputSchema")
    ping_tool = tools.fetch("Workspace--ping")
    assert_equal "Workspace - Ping", ping_tool["title"]
    assert ping_tool["x-mcp-docs-only"]
    refute tools.fetch("list").key?("x-mcp-docs-only")
    assert ping_tool.dig("inputSchema", "properties", "style")
    refute ping_tool["inputSchema"].key?("fields")
    ping_description = ping_tool["description"]
    ping_access_at = ping_description.index("Access: View.")
    ping_tool_at = ping_description.index("Tool: capability_action")
    refute_includes ping_description, "Tool name:"
    refute_includes ping_description, "Runs on a "
    refute_includes ping_description, "Type: `Workspace`"
    assert_includes ping_description, "Access: View."
    assert_operator ping_tool_at, :>, ping_access_at
    refute_includes tools.fetch("ping")["description"], "Access:"
    refute_includes ping_tool["description"], "Allowed operations:"
    refute_includes ping_tool["description"], "Writable fields:"
    assert_includes ping_tool["description"], "Tool: capability_action with type `Workspace` and action `ping`"
    refute_includes ping_tool["description"], "style"
    tag_names = spec.fetch("tags").map { |tag| tag["name"] }
    assert_includes tag_names, "Core"
    assert_includes tag_names, "Endpoints"
    refute_includes tag_names, "Types"
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
    refute_includes schemas.keys, "Workspace"
    refute_includes schemas.keys, "Folder"
    assert_includes schemas.keys, "TypeName"
    description = spec.dig("info", "description")
    refute_includes description, "Call describe before create"
    refute_includes description, "## Records and parents"
    assert_includes description, "## Endpoint tools"
    assert_includes description, "## Authentication"
    ping = spec.dig("x-mcp", "tools").find { |tool| tool["name"] == "ops_ping" }
    assert_equal ["Endpoints"], ping["tags"]
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
