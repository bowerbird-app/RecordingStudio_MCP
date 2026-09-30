# frozen_string_literal: true

require "test_helper"

class AdminTest < Minitest::Test
  def test_register_is_idempotent_for_the_mcp_section
    RecordingStudioMcp::Admin.register!
    RecordingStudioMcp::Admin.register!

    section = RecordingStudioAdmin.section_for("mcp")

    assert_equal "RecordingStudioMcp::Admin::McpSection", section.name
    assert_equal "MCP", section.title
    assert_equal "What clients are offered.", section.subtitle
    assert_equal %w[mcp.server mcp.tools mcp.skills mcp.instructions], section.widget_keys
    assert_nil RecordingStudioAdmin.screen_for("mcp")
    mcp_sections = RecordingStudioAdmin.sections.keys.count { |key| key == "mcp" }
    assert_equal 1, mcp_sections
    assert_equal "Server", RecordingStudioMcp::Admin::ServerWidget.resolve(nil).title
    assert_equal "Name, version, and the paths clients use.", RecordingStudioMcp::Admin::ServerWidget.resolve(nil).info
    assert_equal "Tools", RecordingStudioMcp::Admin::ToolsWidget.resolve(nil).title
    assert_equal "What this server can do.", RecordingStudioMcp::Admin::ToolsWidget.resolve(nil).info
    assert_equal "Skills", RecordingStudioMcp::Admin::SkillsWidget.resolve(nil).title
    assert_equal "Registered here. Exposed is what a new client is offered.",
                 RecordingStudioMcp::Admin::SkillsWidget.resolve(nil).info
    assert_equal "Instructions", RecordingStudioMcp::Admin::InstructionsWidget.resolve(nil).title
    assert_equal "Sent when a client connects.", RecordingStudioMcp::Admin::InstructionsWidget.resolve(nil).info
  end

  def test_skill_and_tool_items_follow_registration_and_exposure
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        RecordingStudioMcp.register_skill("research-publications", path: __FILE__)
        RecordingStudioMcp.register_skill(
          "hidden-notes",
          path: __FILE__,
          available_if: ->(access_grant:) { access_grant.present? }
        )

        assert_equal [
          { text: "research-publications", trailing: "Registered, exposed" },
          { text: "hidden-notes", trailing: "Registered only" }
        ], RecordingStudioMcp::Admin.skill_items
        assert_includes RecordingStudioMcp::Admin.tool_items, { text: "list", trailing: "List records" }
        assert_equal [
          { leading: "Name", text: "recording-studio" },
          { leading: "Version", text: RecordingStudioMcp::VERSION },
          { leading: "Protocol", text: "2025-06-18" },
          { leading: "Endpoint", text: "/recording_studio_mcp" },
          { leading: "Discovery", text: "/.well-known/oauth-protected-resource/recording_studio_mcp" },
          { leading: "Oauth", text: "/recording_studio_oauth" }
        ], RecordingStudioMcp::Admin.server_items
      end
    end
  end

  def test_empty_tool_and_skill_lists_say_none
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        assert_equal [{ text: "None" }], RecordingStudioMcp::Admin.tool_items
        assert_equal [{ text: "None" }], RecordingStudioMcp::Admin.skill_items
      end
    end
  end

  def test_configuration_error_lists_tools_and_instructions_without_blanking_the_server
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        RecordingStudioApi.register_endpoint(
          :list,
          http_verb: :get,
          path: "custom-list",
          handler: ->(_context) { { ok: true } }
        )
        error = assert_raises(RecordingStudioApi::ConfigurationError) do
          RecordingStudioMcp::Tools.definitions(api: nil)
        end

        assert_equal [{ text: "Tools could not be listed. #{error.message}" }], RecordingStudioMcp::Admin.tool_items
        assert_equal [{ text: "Instructions could not be loaded. #{error.message}" }],
                     RecordingStudioMcp::Admin.instruction_items
        assert_includes RecordingStudioMcp::Admin.server_items, { leading: "Name", text: "recording-studio" }
        assert_equal RecordingStudioMcp::Admin.tool_items, RecordingStudioMcp::Admin::ToolsWidget.resolve(nil).items
        assert_equal [{ text: "None" }], RecordingStudioMcp::Admin.skill_items
      end
    end
  end

  def test_skill_hook_errors_propagate
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_skill(
        "broken-notes",
        path: __FILE__,
        available_if: ->(access_grant:) { raise "hook failed" if access_grant.nil? }
      )

      error = assert_raises(RuntimeError) { RecordingStudioMcp::Admin.skill_items }

      assert_equal "hook failed", error.message
    end
  end

  def test_reload_replaces_widgets_and_keeps_one_section
    RecordingStudioMcp::Admin.register!
    previous = RecordingStudioAdmin.widget_for("mcp.tools")

    silence_warnings do
      load previous.source_location.first
    end
    RecordingStudioMcp::Admin.register!

    current = RecordingStudioAdmin.widget_for("mcp.tools")

    refute_same previous, current
    assert_equal previous.source_location, current.source_location
    assert_equal "RecordingStudioMcp::Admin::McpSection", RecordingStudioAdmin.section_for("mcp").name
    mcp_sections = RecordingStudioAdmin.sections.keys.count { |key| key == "mcp" }
    tool_widgets = RecordingStudioAdmin.registry.widgets.keys.count { |key| key == "mcp.tools" }
    assert_equal 1, mcp_sections
    assert_equal 1, tool_widgets
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
