# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
    module_function

    def execute_catalog(tool, arguments, access_grant, progress_reporter: nil)
      RecordingStudioMetrics::Api::ExecuteHandler.call(
        catalog_endpoint_context(tool, arguments, access_grant, progress_reporter)
      )
    end

    def catalog_params_for(tool, arguments)
      params = {}
      catalog_each_argument(arguments) { |key, value| catalog_assign_argument(tool, params, key, value) }
      params[:resource] = tool.resource
      params[:name] = tool.metric_name
      params
    end

    def catalog_endpoint_context(tool, arguments, access_grant, progress_reporter)
      RecordingStudioApi::RegisteredEndpointContext.new(
        api_client: access_grant.api_client,
        credential: grant_value(access_grant, :credential),
        access_recording: grant_value(access_grant, :access_recording),
        access_grant: access_grant,
        root_recording: grant_value(access_grant, :root_recording),
        params: catalog_params_for(tool, arguments),
        progress_reporter: progress_reporter
      )
    end

    def catalog_each_argument(arguments)
      catalog_argument_hash(arguments).each { |key, value| yield key.to_s, value }
    end

    def catalog_argument_hash(arguments)
      return {} if arguments.nil?
      return arguments if arguments.is_a?(Hash)
      return arguments.to_unsafe_h if arguments.respond_to?(:to_unsafe_h)

      raise RecordingStudioApi::InvalidActionInputError, "Tool arguments must be an object"
    end

    def catalog_assign_argument(tool, params, key, value)
      return if value.nil?
      unless tool.plan.passthrough.include?(key)
        raise RecordingStudioApi::InvalidActionInputError, "Unknown argument #{key}"
      end
      return catalog_assign_filters(params, value) if key == "filters"

      raise RecordingStudioApi::InvalidActionInputError, "#{key} must be a string" unless value.is_a?(String)

      params[key.to_sym] = value
    end

    def catalog_assign_filters(params, value)
      raise RecordingStudioApi::InvalidActionInputError, "filters must be an object" unless value.is_a?(Hash)

      params[:filters] = value.each_with_object({}) do |(filter_name, filter_value), folded|
        next if filter_value.nil?

        folded[filter_name.to_sym] = filter_value
      end
    end
    private_class_method :catalog_endpoint_context, :catalog_each_argument, :catalog_argument_hash,
                         :catalog_assign_argument, :catalog_assign_filters
  end
end
