# frozen_string_literal: true

module RecordingStudioMcp
  module RecordableMetricTools
    module_function

    def collect(catalog)
      tools = catalog.type_names.flat_map { |type_name| tools_for(catalog, type_name) }
      tools.sort_by { |tool| tool.name.to_s }.freeze
    end

    def tools_for(catalog, type_name)
      registration = RecordingStudioApi.recordable_registration_for(type_name, api: catalog.api)
      return [] unless registration&.supports_operation?(:index)

      RecordingStudioApi.metrics_for(type_name, api: catalog.api).filter_map do |entry|
        metric_tool_for(catalog, type_name, entry)
      end
    end

    def metric_tool_for(catalog, type_name, entry)
      Tool.new(**tool_fields(catalog, type_name, entry))
    rescue RecordingStudioApi::ConfigurationError => e
      warn_skipped_metric(entry.name, e)
      nil
    end

    def tool_fields(catalog, type_name, entry)
      {
        name: ToolName.from_identifier(entry.name),
        metric_name: entry.name,
        recordable_type: type_name,
        resource_name: RecordingStudioApi.resource_name_for(type_name),
        api: catalog.api,
        description: entry.description,
        plan: ArgumentPlan.from(entry.parameters)
      }
    end

    def warn_skipped_metric(name, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[RecordingStudioMcp] skipped recordable metric #{name}: #{error.message}")
    end
    private_class_method :tools_for, :metric_tool_for, :tool_fields, :warn_skipped_metric
  end
end
