# frozen_string_literal: true

require "test_helper"

class WwwAuthenticateTest < Minitest::Test
  Request = Struct.new(:base_url)

  def test_points_at_oauth_protected_resource_metadata
    request = Request.new("https://studio.example")

    value = RecordingStudioMcp::WwwAuthenticate.header_value(request)

    assert_equal(
      'Bearer resource_metadata="https://studio.example/.well-known/oauth-protected-resource"',
      value
    )
    refute_includes value, "recording_studio_mcp"
  end

  def test_adds_invalid_token_error
    request = Request.new("https://studio.example")

    value = RecordingStudioMcp::WwwAuthenticate.header_value(request, error: "invalid_token")

    assert_includes value, 'error="invalid_token"'
    assert_includes value, "resource_metadata="
  end
end
