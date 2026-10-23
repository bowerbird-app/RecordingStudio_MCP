# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
    module_function

    def recordable_params_for(tool, arguments)
      params = {}
      each_argument(arguments) { |key, value| assign_argument(tool, params, key, value) }
      params["name"] = tool.metric_name
      params["resource"] = tool.resource_name
      params
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
      if key.match?(BRACKET_FILTER_KEY)
        raise RecordingStudioApi::InvalidActionInputError,
              "Send list filters as a filter object of attribute names"
      end
      return assign_filter(params, value) if key == "filter"

      assign_passthrough(tool, params, key, value)
    end

    def assign_filter(params, value)
      return if value.nil?

      folded = fold_filter(value)
      params["filter"] = folded unless folded.empty?
    end

    def fold_filter(value)
      raise RecordingStudioApi::InvalidActionInputError, "filter must be an object" unless value.is_a?(Hash)

      folded = {}
      each_argument(value) do |attribute, attribute_value|
        next if attribute_value.nil?

        folded[attribute] = attribute_value
      end
      folded
    end

    def assign_passthrough(tool, params, key, value)
      known = tool.plan.passthrough.include?(key)
      raise RecordingStudioApi::InvalidActionInputError, "Unknown argument #{key}" unless known
      return if value.nil?
      raise RecordingStudioApi::InvalidActionInputError, "#{key} must be a string" unless value.is_a?(String)

      params[key] = value
    end
    private_class_method :each_argument, :argument_hash, :assign_argument, :assign_filter, :fold_filter,
                         :assign_passthrough
  end
end
