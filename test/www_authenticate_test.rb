# frozen_string_literal: true

require "test_helper"

class WwwAuthenticateTest < Minitest::Test
  Request = Struct.new(:base_url)

  def setup
    @previous_path = RecordingStudioMcp.configuration.oauth_protected_resource_path
    @previous_mount = RecordingStudioMcp.configuration.mcp_mount_path
    RecordingStudioMcp.configuration.mcp_mount_path = "/recording_studio_mcp"
    RecordingStudioMcp.configuration.oauth_protected_resource_path =
      "/.well-known/oauth-protected-resource/recording_studio_mcp"
  end

  def teardown
    RecordingStudioMcp.configuration.oauth_protected_resource_path = @previous_path
    RecordingStudioMcp.configuration.mcp_mount_path = @previous_mount
  end

  def test_points_at_mcp_protected_resource_metadata
    request = Request.new("https://studio.example")

    value = RecordingStudioMcp::WwwAuthenticate.header_value(request)

    assert_equal(
      'Bearer resource_metadata="https://studio.example/.well-known/oauth-protected-resource/recording_studio_mcp"',
      value
    )
    assert_includes value, "recording_studio_mcp"
    refute_includes value, 'resource_metadata="https://studio.example/.well-known/oauth-protected-resource"'
  end

  def test_adds_invalid_token_error
    request = Request.new("https://studio.example")

    value = RecordingStudioMcp::WwwAuthenticate.header_value(request, error: "invalid_token")

    assert_includes value, 'error="invalid_token"'
    assert_includes value, "resource_metadata="
  end
end
