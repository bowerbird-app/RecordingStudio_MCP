# frozen_string_literal: true

require "test_helper"

class NamedApiTest < Minitest::Test
  def test_public_paths_match_the_mcp_mount
    assert_equal "public", RecordingStudioMcp::NamedApi.normalize(nil)
    assert RecordingStudioMcp::NamedApi.public?("public")
    refute RecordingStudioMcp::NamedApi.public?("operations")
    assert_equal "/recording_studio_mcp", RecordingStudioMcp::NamedApi.mcp_path("public")
    assert_equal "/recording_studio_oauth", RecordingStudioMcp::NamedApi.authorization_server_path("public")
    assert_equal "/.well-known/oauth-protected-resource/recording_studio_mcp",
                 RecordingStudioMcp::NamedApi.well_known_path("public")
  end

  def test_named_api_paths_follow_api_and_oauth_conventions
    assert_equal "/recording_studio_mcp/apis/operations", RecordingStudioMcp::NamedApi.mcp_path("operations")
    assert_equal "/recording_studio_oauth/apis/operations",
                 RecordingStudioMcp::NamedApi.authorization_server_path("operations")
    assert_equal "/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations",
                 RecordingStudioMcp::NamedApi.well_known_path("operations")
  end

  def test_from_path_reads_named_api_from_the_mcp_mount
    assert_equal "public", RecordingStudioMcp::NamedApi.from_path("/recording_studio_mcp")
    assert_equal "operations", RecordingStudioMcp::NamedApi.from_path("/recording_studio_mcp/apis/operations")
    assert_equal "public", RecordingStudioMcp::NamedApi.from_path("/other")
  end

  def test_draw_named_api_well_known_is_specific_not_a_glob
    drawn = []
    mapper = Object.new
    mapper.define_singleton_method(:get) { |path, **options| drawn << [path, options] }

    RecordingStudioMcp.draw_named_api_well_known(mapper)

    assert_equal [
      [
        "/.well-known/oauth-protected-resource/recording_studio_mcp/apis/:api_key",
        { to: "recording_studio_mcp/oauth_discoveries#protected_resource" }
      ]
    ], drawn
  end
end
