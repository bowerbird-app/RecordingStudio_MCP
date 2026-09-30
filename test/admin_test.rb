# frozen_string_literal: true

require "test_helper"

class AdminTest < Minitest::Test
  def test_register_is_idempotent_for_the_mcp_section
    RecordingStudioMcp::Admin.register!
    RecordingStudioMcp::Admin.register!

    section = RecordingStudioAdmin.section_for("mcp")

    assert_equal "RecordingStudioMcp::Admin::McpSection", section.name
    assert_equal "MCP admin", section.title
    assert_equal "What clients are offered.", section.subtitle
    assert_equal %w[mcp.usage], section.widget_keys
    assert_equal %i[oauth_apps], section.links.map(&:name)
    assert_nil RecordingStudioAdmin.screen_for("mcp")

    widget = RecordingStudioAdmin.widget_for("mcp.usage").resolve(nil)
    assert_equal "Usage", widget.title
    assert_equal "Calls from the last 7 days.", widget.info
    assert_equal [{ text: "None yet" }], widget.items
    mcp_sections = RecordingStudioAdmin.sections.keys.count { |key| key == "mcp" }
    assert_equal 1, mcp_sections
  end

  def test_reload_keeps_one_section_and_one_link
    RecordingStudioMcp::Admin.register!
    source_path, = Object.const_source_location("RecordingStudioMcp::Admin::McpSection")

    silence_warnings do
      RecordingStudioMcp::Admin.send(:remove_const, :McpSection)
      load source_path
    end
    RecordingStudioMcp::Admin.register!

    section = RecordingStudioAdmin.section_for("mcp")

    assert_equal "RecordingStudioMcp::Admin::McpSection", section.name
    assert_equal "MCP admin", section.title
    assert_equal %w[mcp.usage], section.widget_keys
    assert_equal %i[oauth_apps], section.links.map(&:name)
    mcp_sections = RecordingStudioAdmin.sections.keys.count { |key| key == "mcp" }
    assert_equal 1, mcp_sections
  end

  def test_gemspec_requires_recording_studio_admin_two
    spec = Gem::Specification.load(File.expand_path("../recording_studio_mcp.gemspec", __dir__))
    dependency = spec.runtime_dependencies.find { |runtime| runtime.name == "recording_studio_admin" }

    assert_equal "recording_studio_admin", dependency.name
    assert dependency.requirement.satisfied_by?(Gem::Version.new("2.0.2"))
    refute dependency.requirement.satisfied_by?(Gem::Version.new("1.9.0"))
    refute dependency.requirement.satisfied_by?(Gem::Version.new("3.0.0"))

    admin_source = File.read(File.expand_path("../lib/recording_studio_mcp/admin.rb", __dir__))
    engine_source = File.read(File.expand_path("../lib/recording_studio_mcp/engine.rb", __dir__))

    refute_includes admin_source, "defined?(RecordingStudioAdmin)"
    refute_includes admin_source, "rescue LoadError"
    refute_includes engine_source, "defined?(RecordingStudioAdmin)"
    refute_includes engine_source, "rescue LoadError"
  end
end
