# frozen_string_literal: true

require "test_helper"

class ProtectedResourceMetadataTest < Minitest::Test
  Request = Struct.new(:base_url)

  def setup
    @previous = RecordingStudioMcp.configuration.to_h
    RecordingStudioMcp.configuration.mcp_mount_path = "/recording_studio_mcp"
    RecordingStudioMcp.configuration.oauth_engine_mount_path = "/recording_studio_oauth"
    RecordingStudioMcp.configuration.oauth_protected_resource_path =
      "/.well-known/oauth-protected-resource/recording_studio_mcp"
  end

  def teardown
    RecordingStudioMcp.configuration.merge!(@previous)
  end

  def test_resource_is_the_mcp_url_not_the_api_path
    request = Request.new("https://studio.example")

    document = RecordingStudioMcp::ProtectedResourceMetadata.document(request)

    assert_equal "https://studio.example/recording_studio_mcp", document.fetch(:resource)
    refute_includes document.fetch(:resource), "recording_studio_api"
    assert_equal ["https://studio.example/recording_studio_oauth"], document.fetch(:authorization_servers)
    assert_equal ["header"], document.fetch(:bearer_methods_supported)
  end

  def test_operations_resource_points_at_ops_mcp_and_ops_authorize
    request = Request.new("https://studio.example")

    document = RecordingStudioMcp::ProtectedResourceMetadata.document(request, api_key: "operations")

    assert_equal "https://studio.example/recording_studio_mcp/apis/operations", document.fetch(:resource)
    refute_includes document.fetch(:resource), "recording_studio_api"
    assert_equal ["https://studio.example/recording_studio_oauth/apis/operations"],
                 document.fetch(:authorization_servers)
  end

  def test_well_known_path_follows_rfc_9728_suffix
    assert_equal(
      "/.well-known/oauth-protected-resource/recording_studio_mcp",
      RecordingStudioMcp::ProtectedResourceMetadata.well_known_path
    )
    assert_equal(
      "/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations",
      RecordingStudioMcp::ProtectedResourceMetadata.well_known_path(api_key: "operations")
    )
  end
end
