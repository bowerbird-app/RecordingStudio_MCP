# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module Admin
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
      # A second load reopens this class. widget and link append, so clear the lists first.
      @widget_keys_value = []
      @links_value = []

      key "mcp"
      title "MCP admin"
      subtitle "What clients are offered."
      blast_radius :site
      widget "mcp.usage"
      link :oauth_apps, text: "Registered apps", url: ->(context) { context.admin_section_path("oauth_apps") }
      link :usage, text: "Usage", url: ->(context) { context.admin_screen_path("mcp_usage") }
    end

    module_function

    def register!
      RecordingStudioAdmin.register_widget(UsageWidget)
      RecordingStudioAdmin.register_screen(UsageScreen)
      RecordingStudioAdmin.register_section(McpSection)
    end
  end
end
