# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module Admin
    UsageWidget = RecordingStudioAdmin::Widget.new("mcp.usage") do
      type :list
      title "Usage"
      info "Calls from the last 7 days."
      hide_change
      hide_period
      blast_radius :site
      items { RecordingStudioMcp::Admin.usage_items }
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
    end

    module_function

    def usage_items
      scope = recent_usage
      return [{ text: "None yet" }] if scope.nil?

      calls = scope.sum(:call_count)
      return [{ text: "None yet" }] if calls.zero?

      usage_lines(scope, calls)
    end

    def register!
      RecordingStudioAdmin.register_widget(UsageWidget)
      RecordingStudioAdmin.register_section(McpSection)
    end

    def recent_usage
      return unless usage_metrics_available?

      UsageDailyMetric.where(metric_date: (Date.current - 6)..Date.current)
    end

    def usage_lines(scope, calls)
      items = [
        { leading: "Calls", text: calls.to_s },
        { leading: "Failed", text: scope.sum(:failed_count).to_s }
      ]
      top_subjects(scope).each do |name, count|
        items << { text: name, trailing: count.to_s }
      end
      items
    end

    def usage_metrics_available?
      UsageDailyMetric.table_available?
    rescue StandardError
      false
    end

    def top_subjects(scope)
      scope.where.not(subject_name: "").group(:subject_name).sum(:call_count)
           .sort_by { |_name, count| -count }
           .first(5)
    end
    private_class_method :recent_usage, :usage_lines, :usage_metrics_available?, :top_subjects
  end
end
