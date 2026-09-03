# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioMcp::Configuration.new
  end

  def test_defaults
    assert_equal "/.well-known/oauth-protected-resource", @configuration.oauth_protected_resource_path
    assert_equal "/recording_studio_oauth", @configuration.oauth_engine_mount_path
    assert_equal "2025-06-18", @configuration.protocol_version
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(
      oauth_protected_resource_path: "/oauth/.well-known/oauth-protected-resource",
      protocol_version: "2025-03-26"
    )

    assert_equal "/oauth/.well-known/oauth-protected-resource", @configuration.oauth_protected_resource_path
    assert_equal "2025-03-26", @configuration.protocol_version
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", protocol_version: "2025-03-26")

    refute_respond_to @configuration, :unknown_key
    assert_equal "2025-03-26", @configuration.protocol_version
  end

  def test_merge_with_non_enumerable_is_noop
    @configuration.merge!(nil)

    assert_equal "/.well-known/oauth-protected-resource", @configuration.oauth_protected_resource_path
  end
end
