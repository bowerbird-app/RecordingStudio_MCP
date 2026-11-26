# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    module InsertMetrics
      private

      def live_metric(name)
        live_metrics.find { |metric| metric.name.to_s == name }
      end

      def live_metrics
        return @live_metrics if defined?(@live_metrics)

        recordable = MetricTools.collect_recordable(catalog)
        recordable = [] if recordable.empty? || !metric_view_allowed?
        @live_metrics = recordable + MetricTools.collect_catalog(catalog, @access_grant)
      end

      def metric_view_allowed?
        return true if @access_grant.nil?

        recording = @access_grant.scope_recording || @access_grant.root_recording
        return false if recording.nil?

        @access_grant.authorized?(recording: recording, role: :view)
      end

      def metric_entry(built, metric)
        Entry.new(family: :metric, definition: Tools.metric_tool(built, metric), metric: metric)
      end

      def warn_skipped_metric_collision(name)
        return unless live_metric(name)

        MetricTools.warn_skipped(name, "name collides with an endpoint tool")
      end

      def blocked_metric_name?(key)
        Tools::TREE_NAMES.include?(key) || @by_name.key?(key)
      end

      def blocked_metric_reason(key)
        return "name collides with a tree tool" if Tools::TREE_NAMES.include?(key)

        "name collides with an existing tool"
      end
    end
  end
end
