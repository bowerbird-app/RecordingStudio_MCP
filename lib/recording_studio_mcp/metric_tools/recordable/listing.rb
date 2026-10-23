# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
    module_function

    def collect_recordable(catalog)
      tools = catalog.type_names.flat_map { |type_name| tools_for(catalog, type_name) }
      tools.sort_by { |tool| tool.name.to_s }.freeze
    end

    def tools_for(catalog, type_name)
      registration = RecordingStudioApi.recordable_registration_for(type_name, api: catalog.api)
      return [] unless registration&.supports_operation?(:index)

      metric_entries(registration, type_name, catalog.api).filter_map do |entry|
        metric_tool_for(catalog, type_name, entry)
      end
    end

    def metric_entries(registration, type_name, api)
      RecordingStudioApi.metrics_for(type_name, api: api)
    rescue RecordingStudioApi::ConfigurationError => e
      raise unless unregistered_metric?(e)

      present_entries(registration)
    end

    def unregistered_metric?(error)
      error.message.include?("is not registered with RecordingStudioMetrics")
    end

    def unregistered_error(metric_name)
      RecordingStudioApi::ConfigurationError.new(
        "Metric #{metric_name} is not registered with RecordingStudioMetrics"
      )
    end

    def present_entries(registration)
      registration.metric_names.filter_map do |metric_name|
        definition = RecordingStudioMetrics.find(metric_name)
        if definition.nil?
          warn_skipped(metric_name, unregistered_error(metric_name).message)
          next
        end

        RegisteredEntry.build(registration, definition)
      end
    end

    def metric_tool_for(catalog, type_name, entry)
      Tool.new(**tool_fields(catalog, type_name, entry))
    rescue RecordingStudioApi::ConfigurationError => e
      warn_skipped(entry.name, e.message)
      nil
    end

    def tool_fields(catalog, type_name, entry)
      resource_name = RecordingStudioApi.resource_name_for(type_name)
      {
        name: ToolName.from_identifier(entry.name), metric_name: entry.name, kind: :recordable,
        identifier: entry.name, recordable_type: type_name, resource_name: resource_name, resource: resource_name,
        title: entry.name.to_s.tr("._", " ").capitalize, api: catalog.api, description: entry.description,
        plan: ArgumentPlan.from(entry.parameters)
      }
    end

    private_class_method :tools_for, :metric_entries, :unregistered_metric?, :unregistered_error, :present_entries,
                         :metric_tool_for, :tool_fields
  end
end
