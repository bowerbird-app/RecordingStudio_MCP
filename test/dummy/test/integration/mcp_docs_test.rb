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
    fragment = response.body[%r{<div data-recording-studio-mcp-docs.*?</script>\s*</div>}m]
    assert fragment.present?
    CDN_NEEDLES.each { |needle| refute_includes fragment, needle }
  end

  test "public spec lists registered tools and types" do
    sign_in_user

    get public_api_mcp_docs_openapi_path

    assert_response :success
    spec = JSON.parse(response.body)
    names = spec.dig("x-mcp", "tools").map { |tool| tool["name"] }
    schemas = spec.dig("components", "schemas")

    assert_equal "3.1.0", spec["openapi"]
    assert_includes names, "list"
    assert_includes names, "describe"
    assert_includes schemas.keys, "Workspace"
    assert_includes schemas.keys, "Folder"
    assert_includes schemas.keys, "Page"
    assert_equal "recording://{id}", spec.dig("x-mcp", "resourceTemplates", 0, "uriTemplate")
    refute_empty spec.dig("info", "description")
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
    refute_includes spec.dig("info", "description"), "Call describe before create"
  end

  test "redoc bundle is served locally" do
    sign_in_user

    get "#{public_api_mcp_docs_path}/redoc.js"

    assert_response :success
    assert_includes response.media_type, "javascript"
    refute_includes response.body, "cdn.redocly.com"
    refute_includes response.body, "otel.cloud.redocly.com"
  end

  test "host gate callable allowing access returns 200" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_access = lambda do |controller:, actor:, api:|
      controller.present? && actor.present? && api.present?
    end

    get public_api_mcp_docs_path
    assert_response :success
    get public_api_mcp_docs_openapi_path
    assert_response :success
  end

  test "public access with no actor returns 200" do
    RecordingStudioMcp.configuration.documentation_access = :public

    get public_api_mcp_docs_path
    assert_response :success
    get public_api_mcp_docs_openapi_path
    assert_response :success
    spec = JSON.parse(response.body)
    assert_includes spec.dig("components", "schemas").keys, "Folder"
  end

  test "host gate denies signed-in visitors with 403" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_access = lambda do |controller:, actor:, api:|
      controller && actor && api
      false
    end

    get public_api_mcp_docs_path
    assert_response :forbidden
    get public_api_mcp_docs_openapi_path
    assert_response :forbidden
  end

  test "host gate denies signed-out visitors with 401" do
    RecordingStudioMcp.configuration.documentation_access = lambda do |**|
      false
    end

    get public_api_mcp_docs_path
    assert_response :unauthorized
    get public_api_mcp_docs_openapi_path
    assert_response :unauthorized
  end

  test "authenticated docs require a signed-in actor" do
    get public_api_mcp_docs_path
    assert_response :unauthorized
    get public_api_mcp_docs_openapi_path
    assert_response :unauthorized
  end

  test "disabled documentation is not exposed" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_enabled = false

    get public_api_mcp_docs_path
    assert_response :not_found
    get public_api_mcp_docs_openapi_path
    assert_response :not_found
  end

  private

  def sign_in_user
    user = create_user
    Current.actor = user
    sign_in user
    user
  end
end
