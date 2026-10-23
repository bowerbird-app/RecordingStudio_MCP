# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioMcp
  module Metrics
    RESOURCE = :mcp_calls
    SUBSCRIPTIONS = :mcp_subscriptions
    API = :operations
    EXPOSE = { api: [API] }.freeze
    TOOL_CALLS = ->(relation) { relation.where(method_name: "tools/call") }
    FAILED = ->(relation) { relation.where(failed: true) }
    FAILED_TOOL_CALLS = ->(relation) { relation.where(method_name: "tools/call", failed: true) }
    RATE_LIMITED = ->(relation) { relation.where(rate_limited: true) }
    FAILING = ->(relation) { relation.merge(RecordingStudioMcp::EventSubscription.failing) }
    FAILED_BY_TOOL_DESCRIPTION = "Failed tools/call requests counted from usage logs, by tool name."
    FAILING_DESCRIPTION = "Active, unexpired event subscriptions whose last callback delivery failed " \
                          "(failure_count > 0). They turn inactive after 5 failures in a row."
    AUTHORIZE = ->(context) { RecordingStudioMcp::Api::Access.can_view?(context) }

    module_function

    def register!
      RecordingStudioMetrics.register(
        RESOURCE,
        model: RecordingStudioMcp::UsageLog,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioMcp::Metrics.define_calls(self) }
      register_subscriptions!
    end

    def register_subscriptions!
      RecordingStudioMetrics.register(
        SUBSCRIPTIONS,
        model: RecordingStudioMcp::EventSubscription,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioMcp::Metrics.define_subscriptions(self) }
    end

    def define_subscriptions(dsl)
      dsl.count :failing, title: "Failing MCP event subscriptions", description: FAILING_DESCRIPTION,
                          unit: "count", scope: FAILING, cacheable: false, expose: EXPOSE
    end

    def define_calls(dsl)
      define_over_time(dsl)
      define_failed_over_time(dsl)
      define_by_tool(dsl)
      define_failed_by_tool(dsl)
      define_by_method(dsl)
      define_rate_limited(dsl)
    end

    def define_over_time(dsl)
      dsl.timeseries :over_time,
                     title: "MCP calls over time",
                     field: :occurred_at,
                     measurement: :count,
                     expose: EXPOSE
    end

    def define_failed_over_time(dsl)
      dsl.timeseries :failed_over_time,
                     title: "Failed MCP calls over time",
                     field: :occurred_at,
                     measurement: :count,
                     scope: FAILED,
                     expose: EXPOSE
    end

    def define_by_tool(dsl)
      dsl.breakdown :by_tool,
                    title: "MCP calls by tool",
                    field: :subject_name,
                    measurement: :count,
                    expose: EXPOSE,
                    scope: TOOL_CALLS
    end

    def define_failed_by_tool(dsl)
      dsl.breakdown :failed_by_tool,
                    title: "Failed MCP calls by tool",
                    description: FAILED_BY_TOOL_DESCRIPTION,
                    unit: "count",
                    field: :subject_name,
                    measurement: :count,
                    expose: EXPOSE,
                    scope: FAILED_TOOL_CALLS
    end

    def define_by_method(dsl)
      dsl.breakdown :by_method,
                    title: "MCP calls by method",
                    field: :method_name,
                    measurement: :count,
                    expose: EXPOSE
    end

    def define_rate_limited(dsl)
      dsl.count :rate_limited, title: "Rate limited MCP calls", scope: RATE_LIMITED, expose: EXPOSE
    end
  end
end
