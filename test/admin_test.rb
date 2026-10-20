# frozen_string_literal: true

require "test_helper"

class AdminTest < Minitest::Test
  def test_register_is_idempotent_for_the_mcp_section
    RecordingStudioMcp::Admin.register!
    RecordingStudioMcp::Admin.register!

    section = RecordingStudioAdmin.section_for("mcp")

    assert_equal "RecordingStudioMcp::Admin::McpSection", section.name
    assert_equal "MCP admin", section.title
    assert_equal "Ops MCP connection paths, usage, and failures.", section.subtitle
    assert_equal %w[mcp.failing_subscriptions mcp.ops_connection mcp.failed_by_tool mcp.usage],
                 section.widget_keys
    usages = section.widget_usages.index_by(&:key)
    assert_equal :compact, usages.fetch("mcp.failing_subscriptions").view_variant
    assert_nil usages.fetch("mcp.ops_connection").view_variant
    assert_nil usages.fetch("mcp.failed_by_tool").view_variant
    assert_nil usages.fetch("mcp.usage").view_variant
    assert_equal %i[oauth_apps failing_subscriptions usage], section.links.map(&:name)
    assert_nil RecordingStudioAdmin.screen_for("mcp")

    screen = RecordingStudioAdmin.screen_for("mcp_usage")
    assert_equal "RecordingStudioMcp::Admin::UsageScreen", screen.name
    assert_equal "Usage", screen.title
    assert_equal %i[date_range group_by status failed method], screen.filters.map(&:key)
    assert_equal :modal, screen.filter_presentation
    assert_equal 3, screen.inline_filter_count

    failing_screen = RecordingStudioAdmin.screen_for("mcp_failing_subscriptions")
    assert_equal "RecordingStudioMcp::Admin::FailingSubscriptionsScreen", failing_screen.name
    assert_equal "Failing subscriptions", failing_screen.title

    context = Class.new do
      def admin_screen_path(key)
        "/admin/screens/#{key}"
      end

      def admin_section_path(key)
        "/admin/sections/#{key}"
      end
    end.new
    ops = RecordingStudioAdmin.widget_for("mcp.ops_connection").resolve(context)
    assert_equal :list, ops.type
    assert_equal "Ops MCP", ops.title
    assert_equal "Named API label, not a secret. Do not seed those OauthClients.", ops.info
    assert_equal "Registered apps", ops.link_label
    assert_equal "/admin/sections/oauth_apps", ops.link_to
    assert_equal(
      [
        { text: "MCP URL #{RecordingStudioMcp::NamedApi.mcp_path('operations')}" },
        { text: "Well-known #{RecordingStudioMcp::NamedApi.well_known_path('operations')}" },
        { text: "Register ChatGPT and Grok Bot in Registered apps with api_key: \"operations\"." }
      ],
      ops.items
    )
    failing = RecordingStudioAdmin.widget_for("mcp.failing_subscriptions").resolve(context)
    assert_equal :number, failing.type
    assert_equal "Failing subscriptions", failing.title
    assert_equal "Still listening, but the last callback bounced. They go quiet after five misses in a row.",
                 failing.info
    assert_equal "Open list", failing.link_label
    assert_equal "/admin/screens/mcp_failing_subscriptions", failing.link_to
    assert_equal 0, failing.value

    failed_tools = RecordingStudioAdmin.widget_for("mcp.failed_by_tool").resolve(context)
    assert_equal :list, failed_tools.type
    assert_equal "Failed tools", failed_tools.title
    assert_equal "Tool calls that failed, from daily totals. Usage lists each call.", failed_tools.info
    assert_equal "Usage", failed_tools.link_label
    assert_equal "/admin/screens/mcp_usage?failed=true&method=tools%2Fcall", failed_tools.link_to
    assert_equal [], failed_tools.items

    widget = RecordingStudioAdmin.widget_for("mcp.usage").resolve(context)
    assert_equal :chart, widget.type
    assert_equal :column, widget.chart_type
    assert_equal "Usage", widget.title
    assert_equal "Calls from the last 4 weeks.", widget.info
    assert_equal "Last 4 weeks", widget.metadata[:period_label]
    assert_equal "Usage", widget.link_label
    assert_equal "/admin/screens/mcp_usage", widget.link_to
    assert_equal 0, widget.value
    points = widget.series.first.fetch(:data)
    assert_equal RecordingStudioMcp::UsageWindow.series.first.fetch(:data).size, points.size
    zeros = points.all? { |point| point.fetch(:y).zero? }
    assert zeros
    mcp_sections = RecordingStudioAdmin.sections.keys.count { |key| key == "mcp" }
    assert_equal 1, mcp_sections
  end

  def test_site_metrics_read_recording_studio_metrics_admin
    actor_context = Class.new do
      def current_actor
        :staff
      end

      def admin_screen_path(key)
        "/admin/screens/#{key}"
      end
    end.new
    result = RecordingStudioMetrics::Result.new(
      metric: "mcp_calls.failed_by_tool",
      type: :breakdown,
      data: [
        { key: "show", value: 2 },
        { key: "list", value: 1 },
        { key: "", value: 4 },
        { key: "ping", value: 0 }
      ]
    )

    RecordingStudioMcp::Admin::SiteMetrics.stub(:table_ready?, true) do
      RecordingStudioMetrics::Admin.stub(:scalar_value, 2) do
        assert_equal 2, RecordingStudioMcp::Admin::SiteMetrics.failing_count(actor_context)
      end
    end

    RecordingStudioMcp::Admin::SiteMetrics.stub(:table_ready?, true) do
      RecordingStudioMetrics::Admin.stub(:execute, result) do
        assert_equal(
          [{ text: "show", trailing: "2" }, { text: "list", trailing: "1" }],
          RecordingStudioMcp::Admin::SiteMetrics.failed_tool_items(actor_context)
        )
      end
    end
  end

  def test_usage_failed_filter_keeps_failed_calls
    RecordingStudioMcp::Admin.register!
    filter = RecordingStudioAdmin.screen_for("mcp_usage").filters.find { |item| item.key == :failed }
    relation = Class.new do
      attr_reader :clause

      def where(clause)
        @clause = clause
        self
      end
    end.new

    applied = filter.apply(relation, "true", nil)

    assert_same relation, applied
    assert_equal({ failed: true }, relation.clause)
  end

  def test_reload_keeps_one_section_and_one_link
    RecordingStudioMcp::Admin.register!
    source_path, = Object.const_source_location("RecordingStudioMcp::Admin::McpSection")
    screen_path, = Object.const_source_location("RecordingStudioMcp::Admin::UsageScreen")
    failing_path, = Object.const_source_location("RecordingStudioMcp::Admin::FailingSubscriptionsScreen")

    silence_warnings do
      RecordingStudioMcp::Admin.send(:remove_const, :McpSection)
      RecordingStudioMcp::Admin.send(:remove_const, :UsageScreen)
      RecordingStudioMcp::Admin.send(:remove_const, :FailingSubscriptionsScreen)
      load failing_path
      load screen_path
      load source_path
    end
    RecordingStudioMcp::Admin.register!

    section = RecordingStudioAdmin.section_for("mcp")
    screen = RecordingStudioAdmin.screen_for("mcp_usage")

    assert_equal "RecordingStudioMcp::Admin::McpSection", section.name
    assert_equal "MCP admin", section.title
    assert_equal %w[mcp.failing_subscriptions mcp.ops_connection mcp.failed_by_tool mcp.usage],
                 section.widget_keys
    usages = section.widget_usages.index_by(&:key)
    assert_equal :compact, usages.fetch("mcp.failing_subscriptions").view_variant
    assert_nil usages.fetch("mcp.ops_connection").view_variant
    assert_nil usages.fetch("mcp.failed_by_tool").view_variant
    assert_nil usages.fetch("mcp.usage").view_variant
    assert_equal %i[oauth_apps failing_subscriptions usage], section.links.map(&:name)
    assert_equal %i[date_range group_by status failed method], screen.filters.map(&:key)
    assert_equal :modal, screen.filter_presentation
    assert_equal 3, screen.inline_filter_count
    mcp_sections = RecordingStudioAdmin.sections.keys.count { |key| key == "mcp" }
    usage_screens = RecordingStudioAdmin.screens.keys.count { |key| key == "mcp_usage" }
    failing_screens = RecordingStudioAdmin.screens.keys.count { |key| key == "mcp_failing_subscriptions" }
    assert_equal 1, mcp_sections
    assert_equal 1, usage_screens
    assert_equal 1, failing_screens
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
