# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    def metric_tools?
      recordable_metric_tools? || catalog_metric_tools?
    end

    def recordable_metric_tools?
      @by_name.each_value.any? { |entry| entry.family == :metric && !entry.metric.catalog? }
    end

    def catalog_metric_tools?
      @by_name.each_value.any? { |entry| entry.family == :metric && entry.metric.catalog? }
    end

    def metric_family?(entry)
      entry&.family == :metric
    end
  end
end
