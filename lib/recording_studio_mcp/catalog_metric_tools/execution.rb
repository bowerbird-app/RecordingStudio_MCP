# frozen_string_literal: true

module RecordingStudioMcp
  module CatalogMetricTools
    module_function

    def execute(tool, arguments, access_grant, progress_reporter: nil)
      RecordingStudioMetrics::Api::ExecuteHandler.call(
        endpoint_context(tool, arguments, access_grant, progress_reporter)
      )
    end

    def params_for(tool, arguments)
      params = {}
      each_argument(arguments) { |key, value| assign_argument(tool, params, key, value) }
      params[:resource] = tool.resource
      params[:name] = tool.metric_name
      params
    end

    def endpoint_context(tool, arguments, access_grant, progress_reporter)
      RecordingStudioApi::RegisteredEndpointContext.new(
        api_client: access_grant.api_client,
        credential: grant_value(access_grant, :credential),
        access_recording: grant_value(access_grant, :access_recording),
        access_grant: access_grant,
        root_recording: grant_value(access_grant, :root_recording),
        params: params_for(tool, arguments),
        progress_reporter: progress_reporter,
        **AuthorizedBy.context_keywords(RecordingStudioApi::RegisteredEndpointContext, access_grant)
      )
    end

    def each_argument(arguments)
      argument_hash(arguments).each { |key, value| yield key.to_s, value }
    end

    def argument_hash(arguments)
      return {} if arguments.nil?
      return arguments if arguments.is_a?(Hash)
      return arguments.to_unsafe_h if arguments.respond_to?(:to_unsafe_h)

      raise RecordingStudioApi::InvalidActionInputError, "Tool arguments must be an object"
    end

    def assign_argument(tool, params, key, value)
      return if value.nil?
      unless tool.plan.passthrough.include?(key)
        raise RecordingStudioApi::InvalidActionInputError, "Unknown argument #{key}"
      end
      return assign_filters(params, value) if key == "filters"

      raise RecordingStudioApi::InvalidActionInputError, "#{key} must be a string" unless value.is_a?(String)

      params[key.to_sym] = value
    end

    def assign_filters(params, value)
      raise RecordingStudioApi::InvalidActionInputError, "filters must be an object" unless value.is_a?(Hash)

      params[:filters] = value.each_with_object({}) do |(filter_name, filter_value), folded|
        next if filter_value.nil?

        folded[filter_name.to_sym] = filter_value
      end
    end
    private_class_method :endpoint_context, :each_argument, :argument_hash, :assign_argument, :assign_filters
  end
end
