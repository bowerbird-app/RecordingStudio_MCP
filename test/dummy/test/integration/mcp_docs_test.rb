# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpDocsTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

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

  test "public docs render live host types tools and resource template" do
    sign_in_user

    get public_api_mcp_docs_path

    assert_response :success
    assert_includes response.body, 'data-recording-studio-mcp-docs="public"'
    assert_includes response.body, "Public MCP"
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Page"
    assert_includes response.body, ">list</code>"
    assert_includes response.body, ">describe</code>"
    assert_includes response.body, "recording://{id}"
    assert_includes response.body, "writable_fields"
    assert_includes response.body, "capability_actions"
  end

  test "operations docs render the operations catalog not dummy tree types" do
    sign_in_user

    get operations_api_mcp_docs_path

    assert_response :success
    assert_includes response.body, 'data-recording-studio-mcp-docs="operations"'
    assert_includes response.body, "ops_ping"
    refute_includes response.body, ">Workspace</h3>"
    refute_includes response.body, ">Folder</h3>"
  end

  test "host gate denies signed-in visitors with 403" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_access = lambda do |controller:, actor:, api:|
      controller && actor && api
      false
    end

    get public_api_mcp_docs_path

    assert_response :forbidden
  end

  test "host gate denies signed-out visitors with 401" do
    RecordingStudioMcp.configuration.documentation_access = lambda do |**|
      false
    end

    get public_api_mcp_docs_path

    assert_response :unauthorized
  end

  test "authenticated docs require a signed-in actor" do
    get public_api_mcp_docs_path

    assert_response :unauthorized
  end

  test "disabled documentation is not exposed" do
    sign_in_user
    RecordingStudioMcp.configuration.documentation_enabled = false

    get public_api_mcp_docs_path

    assert_response :not_found
  end

  test "unknown oauth client id stays on the named API" do
    sign_in_user

    get public_api_mcp_docs_path, params: { oauth_client_id: "missing-client" }

    assert_response :success
    assert_includes response.body, "Folder"
  end

  private

  def sign_in_user
    user = create_user
    Current.actor = user
    sign_in user
    user
  end
end
