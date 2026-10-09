# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioMcp
  module Metrics
    RESOURCE = :mcp_calls
    API = :operations
    EXPOSE = { api: [API] }.freeze
    TOOL_CALLS = ->(relation) { relation.where(method_name: "tools/call") }
    AUTHORIZE = ->(context) { RecordingStudioMcp::Api::Access.can_view?(context) }

    module_function

    def register!
      RecordingStudioMetrics.register(
        RESOURCE,
        model: UsageDailyMetric,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioMcp::Metrics.define_calls(self) }
    end

    def define_calls(dsl)
      define_over_time(dsl)
      define_failed_over_time(dsl)
      define_by_tool(dsl)
      define_by_method(dsl)
      define_rate_limited(dsl)
    end

    def define_over_time(dsl)
      dsl.timeseries :over_time,
                     title: "MCP calls over time",
                     field: :metric_date,
                     measurement: :sum,
                     value_field: :call_count,
                     expose: EXPOSE
    end

    def define_failed_over_time(dsl)
      dsl.timeseries :failed_over_time,
                     title: "Failed MCP calls over time",
                     field: :metric_date,
                     measurement: :sum,
                     value_field: :failed_count,
                     expose: EXPOSE
    end

    def define_by_tool(dsl)
      dsl.breakdown :by_tool,
                    title: "MCP calls by tool",
                    field: :subject_name,
                    measurement: :sum,
                    value_field: :call_count,
                    expose: EXPOSE,
                    scope: TOOL_CALLS
    end

    def define_by_method(dsl)
      dsl.breakdown :by_method,
                    title: "MCP calls by method",
                    field: :method_name,
                    measurement: :sum,
                    value_field: :call_count,
                    expose: EXPOSE
    end

    def define_rate_limited(dsl)
      dsl.sum :rate_limited, title: "Rate limited MCP calls", field: :rate_limited_count, expose: EXPOSE
    end
  end
end
