# frozen_string_literal: true

require "recording_studio_admin"
require "recording_studio_metrics"

module RecordingStudioMcp
  module Admin
    OPS_API_KEY = "operations"

    module SiteMetrics
      FAILING = "mcp_subscriptions.failing"
      FAILED_BY_TOOL = "mcp_calls.failed_by_tool"
      SITE = { scope: :site, site_authorized: true }.freeze

      module_function

      def failing_count(admin_context)
        return 0 unless table_ready?("EventSubscription")

        RecordingStudioMetrics::Admin.scalar_value(FAILING, admin_context: admin_context, **SITE)
      end

      def failed_tool_items(admin_context)
        return [] unless table_ready?("UsageLog")

        result = RecordingStudioMetrics::Admin.execute(FAILED_BY_TOOL, admin_context: admin_context, **SITE)
        Array(result.data).filter_map { |row| item_for(row) }.sort_by do |item|
          [-item[:trailing].to_i, item[:text]]
        end
      end

      def item_for(row)
        name = (row[:key] || row["key"]).to_s
        count = row[:value] || row["value"]
        return if name.blank? || count.to_i.zero?

        { text: name, trailing: count.to_i.to_s }
      end

      def table_ready?(name)
        RecordingStudioMcp.const_get(name).table_available?
      rescue NameError
        false
      end
    end

    OpsConnectionWidget = RecordingStudioAdmin::Widget.new("mcp.ops_connection") do
      type :list
      title "Ops MCP"
      info "Named API label, not a secret. Do not seed those OauthClients."
      hide_change
      hide_period
      hide_metric
      blast_radius :site
      list_options divider: true
      items do
        [
          { text: "MCP URL #{NamedApi.mcp_path(OPS_API_KEY)}" },
          { text: "Well-known #{NamedApi.well_known_path(OPS_API_KEY)}" },
          { text: "Register ChatGPT and Grok Bot in Registered apps with api_key: \"operations\"." }
        ]
      end
      link_to { |context| context.admin_section_path("oauth_apps") }
      link_label "Registered apps"
    end

    FailingSubscriptionsWidget = RecordingStudioAdmin::Widget.new("mcp.failing_subscriptions") do
      type :number
      title "Failing subscriptions"
      info "Still listening, but the last callback bounced. They go quiet after five misses in a row."
      hide_change
      hide_period
      blast_radius :site
      value { |context| SiteMetrics.failing_count(context) }
      link_to { |context| context.admin_screen_path("mcp_failing_subscriptions") }
      link_label "Open list"
    end

    FailedByToolWidget = RecordingStudioAdmin::Widget.new("mcp.failed_by_tool") do
      type :list
      title "Failed tools"
      info "Tool calls that failed. Usage lists each call."
      hide_change
      hide_period
      hide_metric
      blast_radius :site
      list_options divider: true
      items { |context| SiteMetrics.failed_tool_items(context) }
      link_to { |context| UsageWindow.failed_calls_path(context) }
      link_label "Usage"
    end

    UsageWidget = RecordingStudioAdmin::Widget.new("mcp.usage") do
      type :chart
      title "Usage"
      info "Calls from the last 4 weeks."
      chart_type :column
      hide_change
      blast_radius :site
      value { RecordingStudioMcp::UsageWindow.total }
      metadata { { period_label: "Last 4 weeks" } }
      series { RecordingStudioMcp::UsageWindow.series }
      chart_options do
        {
          height: 240,
          plotOptions: { bar: { horizontal: false, columnWidth: "52%" } },
          xaxis: { labels: { rotate: 0, hideOverlappingLabels: true } },
          yaxis: { min: 0, forceNiceScale: true },
          dataLabels: { enabled: false },
          stroke: { width: 0 }
        }
      end
      link_to { |context| RecordingStudioMcp::UsageWindow.screen_path(context) }
      link_label "Usage"
    end

    class McpSection < RecordingStudioAdmin::Section
      @widget_keys_value = []
      @links_value = []

      key "mcp"
      title "MCP admin"
      subtitle "Ops MCP connection paths, usage, and failures."
      blast_radius :site
      widget "mcp.failing_subscriptions", view_variant: :compact
      widget "mcp.ops_connection"
      widget "mcp.failed_by_tool"
      widget "mcp.usage"
      link :oauth_apps, text: "Registered apps", url: ->(context) { context.admin_section_path("oauth_apps") }
      link :failing_subscriptions, text: "Failing subscriptions",
                                   url: ->(context) { context.admin_screen_path("mcp_failing_subscriptions") }
      link :usage, text: "Usage", url: ->(context) { context.admin_screen_path("mcp_usage") }
    end

    module_function

    def register!
      RecordingStudioAdmin.register_widget(OpsConnectionWidget)
      RecordingStudioAdmin.register_widget(FailingSubscriptionsWidget)
      RecordingStudioAdmin.register_widget(FailedByToolWidget)
      RecordingStudioAdmin.register_widget(UsageWidget)
      RecordingStudioAdmin.register_screen(UsageScreen)
      RecordingStudioAdmin.register_screen(FailingSubscriptionsScreen)
      RecordingStudioAdmin.register_section(McpSection)
    end
  end
end
