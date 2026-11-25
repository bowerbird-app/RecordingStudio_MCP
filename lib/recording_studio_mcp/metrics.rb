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
    FAILING = ->(relation) { relation.merge(EventSubscription.failing) }
    OVER_TIME_DESCRIPTION = "Sum of MCP request counts by day from daily usage rollups."
    FAILED_OVER_TIME_DESCRIPTION = "Sum of failed MCP request counts by day from daily usage rollups."
    BY_TOOL_DESCRIPTION = "Sum of tools/call counts by tool name from daily usage rollups."
    FAILED_BY_TOOL_DESCRIPTION = "Sum of failed tools/call counts by tool name from daily usage rollups."
    BY_METHOD_DESCRIPTION = "Sum of MCP request counts by JSON-RPC method from daily usage rollups."
    RATE_LIMITED_DESCRIPTION = "Sum of rate-limited MCP request counts from daily usage rollups."
    FAILING_DESCRIPTION = "Count of active, unexpired event subscriptions whose last callback failed " \
                          "(failure_count greater than 0). They turn inactive after 5 failures in a row."
    AUTHORIZE = ->(context) { RecordingStudioMcp::Api::Access.can_view?(context) }

    module_function

    def register!
      RecordingStudioMetrics.register(
        RESOURCE,
        model: UsageDailyMetric,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioMcp::Metrics.define_calls(self) }
      register_subscriptions!
    end

    def register_subscriptions!
      RecordingStudioMetrics.register(
        SUBSCRIPTIONS,
        model: EventSubscription,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioMcp::Metrics.define_subscriptions(self) }
    end

    def define_subscriptions(dsl)
      dsl.count :failing, title: "Failing event subscriptions", description: FAILING_DESCRIPTION,
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
                     title: "Calls over time",
                     description: OVER_TIME_DESCRIPTION,
                     field: :metric_date,
                     measurement: :sum,
                     value_field: :call_count,
                     expose: EXPOSE
    end

    def define_failed_over_time(dsl)
      dsl.timeseries :failed_over_time,
                     title: "Failed calls over time",
                     description: FAILED_OVER_TIME_DESCRIPTION,
                     field: :metric_date,
                     measurement: :sum,
                     value_field: :failed_count,
                     expose: EXPOSE
    end

    def define_by_tool(dsl)
      dsl.breakdown :by_tool,
                    title: "Calls by tool",
                    description: BY_TOOL_DESCRIPTION,
                    field: :subject_name,
                    measurement: :sum,
                    value_field: :call_count,
                    expose: EXPOSE,
                    scope: TOOL_CALLS
    end

    def define_failed_by_tool(dsl)
      dsl.breakdown :failed_by_tool,
                    title: "Failed calls by tool",
                    description: FAILED_BY_TOOL_DESCRIPTION,
                    unit: "count",
                    field: :subject_name,
                    measurement: :sum,
                    value_field: :failed_count,
                    expose: EXPOSE,
                    scope: TOOL_CALLS
    end

    def define_by_method(dsl)
      dsl.breakdown :by_method,
                    title: "Calls by method",
                    description: BY_METHOD_DESCRIPTION,
                    field: :method_name,
                    measurement: :sum,
                    value_field: :call_count,
                    expose: EXPOSE
    end

    def define_rate_limited(dsl)
      dsl.sum :rate_limited, title: "Rate limited calls", description: RATE_LIMITED_DESCRIPTION,
                             field: :rate_limited_count, expose: EXPOSE
    end
  end
end
