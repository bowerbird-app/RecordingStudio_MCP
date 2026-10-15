# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    METRIC_FAMILIES = %i[metric catalog_metric].freeze

    def metric_tools?
      recordable_metric_tools? || catalog_metric_tools?
    end

    def recordable_metric_tools?
      @by_name.each_value.any? { |entry| entry.family == :metric }
    end

    def catalog_metric_tools?
      @by_name.each_value.any? { |entry| entry.family == :catalog_metric }
    end

    def metric_family?(entry)
      METRIC_FAMILIES.include?(entry&.family)
    end
  end
end
