# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioMcp::Configuration.new
  end

  def test_defaults
    assert_equal "/recording_studio_mcp", @configuration.mcp_mount_path
    assert_equal "/.well-known/oauth-protected-resource/recording_studio_mcp",
                 @configuration.oauth_protected_resource_path
    assert_equal "/recording_studio_oauth", @configuration.oauth_engine_mount_path
    assert_equal "2025-06-18", @configuration.protocol_version
    assert_equal(
      %w[2025-03-26 2025-06-18 2025-11-25 2026-07-28],
      RecordingStudioMcp::Configuration::SUPPORTED_PROTOCOL_VERSIONS
    )
    assert_equal [], @configuration.allowed_origins
    assert_nil @configuration.instructions_suffix
    assert_nil @configuration.skill_policy
    assert_includes @configuration.to_h.keys, :mcp_mount_path
    assert_includes @configuration.to_h.keys, :instructions_suffix
    assert_includes @configuration.to_h.keys, :skill_policy
    assert_nil @configuration.to_h[:instructions_suffix]
    assert_nil @configuration.to_h[:skill_policy]
    assert_equal false, @configuration.events_enabled
    assert_equal 24.hours, @configuration.event_subscription_ttl
    assert_equal 50, @configuration.event_subscriptions_per_principal
    assert_nil @configuration.event_callback_host_allowed
    assert_includes @configuration.to_h.keys, :events_enabled
    refute_includes @configuration.to_h.keys, :skill_catalog
    refute_includes @configuration.to_h.keys, :event_catalog
    refute_respond_to @configuration, :skill_catalog=
    refute_respond_to @configuration, :event_catalog=
    assert @configuration.event_catalog.empty?
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(
      oauth_protected_resource_path: "/.well-known/oauth-protected-resource/mcp",
      mcp_mount_path: "/mcp",
      protocol_version: "2025-03-26",
      allowed_origins: ["https://assistant.example"],
      instructions_suffix: "Fetch item detail before you draw a screen.",
      skill_policy: ->(skill:, access_grant:) { skill && access_grant }
    )

    assert_equal "/.well-known/oauth-protected-resource/mcp", @configuration.oauth_protected_resource_path
    assert_equal "/mcp", @configuration.mcp_mount_path
    assert_equal "2025-03-26", @configuration.protocol_version
    assert_equal ["https://assistant.example"], @configuration.allowed_origins
    assert_equal "Fetch item detail before you draw a screen.", @configuration.instructions_suffix
    assert_equal "Fetch item detail before you draw a screen.", @configuration.to_h[:instructions_suffix]
    assert @configuration.skill_policy.respond_to?(:call)
    assert_same @configuration.skill_policy, @configuration.to_h[:skill_policy]
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", protocol_version: "2025-03-26")

    refute_respond_to @configuration, :unknown_key
    assert_equal "2025-03-26", @configuration.protocol_version
  end

  def test_merge_with_non_enumerable_is_noop
    @configuration.merge!(nil)

    assert_equal "/.well-known/oauth-protected-resource/recording_studio_mcp",
                 @configuration.oauth_protected_resource_path
  end
end
