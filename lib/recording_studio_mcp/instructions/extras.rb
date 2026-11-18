# frozen_string_literal: true

module RecordingStudioMcp
  module Instructions
    module_function

    def live_section
      return unless RecordingStudioMcp.events_registered?

      section(
        "Live updates",
        [
          "List and read accessible items as resources.",
          "Subscribe to a resource URI to be told when that item changes, then read it again."
        ]
      )
    end

    def metrics_section(surface)
      section("Metrics", recordable_metric_lines(surface) + catalog_metric_lines(surface))
    end

    def recordable_metric_lines(surface)
      return [] unless surface.recordable_metric_tools?

      [
        "Recordable metric tools are read-only. Their arguments are that metric's query parameters.",
        "Pass list filters as a filter object of attribute names."
      ]
    end

    def catalog_metric_lines(surface)
      return [] unless surface.catalog_metric_tools?

      [
        "API metric tools are read-only. A timeseries takes from and to.",
        "start and start_at are the same as from. end and end_at are the same as to.",
        "Pass filters as a filters object."
      ]
    end

    def named_routes_section(surface)
      return unless surface.endpoints_enabled? && !surface.tree_enabled?

      section(
        "If you only see named route tools",
        [
          "That is the whole set.",
          "One tool per named route. Path parameters are arguments."
        ]
      )
    end

    private_class_method :live_section, :metrics_section, :recordable_metric_lines, :catalog_metric_lines,
                         :named_routes_section
  end
end
