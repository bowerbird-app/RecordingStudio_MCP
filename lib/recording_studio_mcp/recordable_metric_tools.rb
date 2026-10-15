# frozen_string_literal: true

require "action_controller"

module RecordingStudioMcp
  module RecordableMetricTools
    TOOL_NAME_PATTERN = /\A[a-z][a-z0-9_]*-[a-z][a-z0-9_]*\z/
    FILTER_PARAMETER = /\Afilter\[(.+)\]\z/
    BRACKET_FILTER_KEY = /\Afilter\[.+\]\z/
    FILTER_DESCRIPTION = "Exact-match list filters. Keys are attribute names. The API reads this as params[:filter]."

    ToolName = Data.define(:value) do
      def self.from_identifier(metric_name)
        new(value: metric_name.to_s.sub(".", "-"))
      end

      def initialize(value:)
        value = value.to_s
        unless value.match?(TOOL_NAME_PATTERN) && value.length <= 64
          raise RecordingStudioApi::ConfigurationError,
                "Metric tool name #{value} is not a hyphenated recordable metric"
        end

        super(value: value.freeze)
      end

      def to_s
        value
      end
    end

    Tool = Data.define(
      :name, :metric_name, :recordable_type, :resource_name, :api, :description, :plan
    ) do
      def initialize(**fields)
        super(**freeze_fields(checked_fields(fields)))
      end

      def title
        metric_name.tr("._", " ").capitalize
      end

      def definition_options
        {
          name: name.to_s, title: title, description: description.presence || title,
          read_only: true, destructive: false, idempotent: true,
          required: plan.required, properties: plan.properties,
          additional_properties: false, api: api
        }
      end

      private

      def checked_fields(fields)
        name = fields.fetch(:name)
        plan = fields.fetch(:plan)
        metric_name = fields.fetch(:metric_name).to_s
        raise ArgumentError, "Metric tool name must be a ToolName" unless name.is_a?(ToolName)
        raise ArgumentError, "Metric tool plan must be an ArgumentPlan" unless plan.is_a?(ArgumentPlan)
        unless name == ToolName.from_identifier(metric_name)
          raise RecordingStudioApi::ConfigurationError, "Metric tool name #{name} does not match #{metric_name}"
        end

        fields.merge(name: name, plan: plan, metric_name: metric_name)
      end

      def freeze_fields(fields)
        fields.merge(
          metric_name: fields.fetch(:metric_name).freeze,
          recordable_type: fields.fetch(:recordable_type).to_s.freeze,
          resource_name: fields.fetch(:resource_name).to_s.freeze,
          api: fields.fetch(:api).to_s.freeze,
          description: fields[:description]&.to_s&.freeze
        )
      end
    end

    class ArgumentPlan
      attr_reader :properties, :required, :filter_attributes, :passthrough

      def self.from(parameters)
        builder = Builder.new
        Array(parameters).each { |parameter| builder.add(parameter) }
        builder.to_plan
      end

      def self.property_schema(parameter)
        schema = parameter.fetch(:schema).dup
        description = parameter[:description]
        schema[:description] = description if description.present?
        schema
      end

      def initialize(properties:, required:, filter_attributes:, passthrough:)
        @properties = deep_freeze(properties)
        @required = deep_freeze(required)
        @filter_attributes = deep_freeze(filter_attributes)
        @passthrough = deep_freeze(passthrough)
        freeze
      end

      class Builder
        def initialize
          @properties = {}
          @required = []
          @filter_properties = {}
          @filter_attributes = []
          @passthrough = []
        end

        def add(parameter)
          name = parameter.fetch(:name).to_s
          reject_invalid!(name, parameter.fetch(:in).to_s)
          attribute = name[FILTER_PARAMETER, 1]
          if attribute
            add_filter(attribute, parameter)
          else
            add_passthrough(name, parameter)
          end
        end

        def to_plan
          attach_filter
          ArgumentPlan.new(
            properties: @properties,
            required: @required,
            filter_attributes: @filter_attributes,
            passthrough: @passthrough
          )
        end

        private

        def reject_invalid!(name, location)
          unless location == "query"
            raise RecordingStudioApi::ConfigurationError, "Metric parameter #{name} must be in query"
          end
          return unless name == "filter"

          raise RecordingStudioApi::ConfigurationError,
                "Metric parameter named filter is reserved for the filter object"
        end

        def add_filter(attribute, parameter)
          @filter_properties[attribute.to_sym] = ArgumentPlan.property_schema(parameter)
          @filter_attributes << attribute
        end

        def add_passthrough(name, parameter)
          @properties[name.to_sym] = ArgumentPlan.property_schema(parameter)
          @passthrough << name
          @required << name if parameter[:required]
        end

        def attach_filter
          return if @filter_attributes.empty?

          @properties[:filter] = {
            type: "object",
            additionalProperties: false,
            description: FILTER_DESCRIPTION,
            properties: @filter_properties
          }
        end
      end
      private_constant :Builder

      private

      def deep_freeze(value)
        case value
        when Hash then freeze_hash(value)
        when Array then value.each { |child| deep_freeze(child) }.freeze
        when String then value.freeze
        else value
        end
      end

      def freeze_hash(value)
        value.each_key { |key| deep_freeze(key) }
        value.each_value { |child| deep_freeze(child) }
        value.freeze
      end
    end

    module_function

    def collect(catalog)
      tools = catalog.type_names.flat_map { |type_name| tools_for(catalog, type_name) }
      tools.sort_by { |tool| tool.name.to_s }.freeze
    end

    def params_for(tool, arguments)
      params = {}
      each_argument(arguments) { |key, value| assign_argument(tool, params, key, value) }
      params["name"] = tool.metric_name
      params["resource"] = tool.resource_name
      params
    end

    def execute(tool, arguments, access_grant)
      RecordingStudioApi::Services::ResourceMetrics::Show.call(
        operation_context(tool, arguments, access_grant)
      )
    end

    def tools_for(catalog, type_name)
      RecordingStudioApi.metrics_for(type_name, api: catalog.api).map do |entry|
        metric_tool_for(catalog, type_name, entry)
      end
    end

    def metric_tool_for(catalog, type_name, entry)
      Tool.new(
        name: ToolName.from_identifier(entry.name),
        metric_name: entry.name,
        recordable_type: type_name,
        resource_name: RecordingStudioApi.resource_name_for(type_name),
        api: catalog.api,
        description: entry.description,
        plan: ArgumentPlan.from(entry.parameters)
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
      if key.match?(BRACKET_FILTER_KEY)
        raise RecordingStudioApi::InvalidActionInputError,
              "Send list filters as a filter object of attribute names"
      end
      return assign_filter(tool, params, value) if key == "filter"

      assign_passthrough(tool, params, key, value)
    end

    def assign_filter(tool, params, value)
      return if value.nil?

      folded = fold_filter(tool, value)
      params["filter"] = folded unless folded.empty?
    end

    def fold_filter(tool, value)
      raise RecordingStudioApi::InvalidActionInputError, "filter must be an object" unless value.is_a?(Hash)

      folded = {}
      each_argument(value) do |attribute, attribute_value|
        stored = filter_value(tool, attribute, attribute_value)
        folded[attribute] = stored unless stored.nil?
      end
      folded
    end

    def filter_value(tool, attribute, attribute_value)
      known = tool.plan.filter_attributes.include?(attribute)
      raise RecordingStudioApi::InvalidActionInputError, "Unknown filter attribute #{attribute}" unless known
      return if attribute_value.nil?
      unless attribute_value.is_a?(String)
        raise RecordingStudioApi::InvalidActionInputError, "filter #{attribute} must be a string"
      end

      attribute_value
    end

    def assign_passthrough(tool, params, key, value)
      known = tool.plan.passthrough.include?(key)
      raise RecordingStudioApi::InvalidActionInputError, "Unknown argument #{key}" unless known
      return if value.nil?
      raise RecordingStudioApi::InvalidActionInputError, "#{key} must be a string" unless value.is_a?(String)

      params[key] = value
    end

    def operation_context(tool, arguments, access_grant)
      RecordingStudioApi::ResourceOperationContext.new(**metric_context(tool, arguments, access_grant))
    end

    def metric_context(tool, arguments, access_grant)
      {
        recording: nil, parent_recording: nil, idempotency_key: nil,
        recordable_type: tool.recordable_type, resource_name: tool.resource_name,
        api_client: access_grant.api_client, credential: access_grant.credential,
        access_recording: access_grant.access_recording, access_grant: access_grant,
        root_recording: access_grant.root_recording,
        api_version: RecordingStudioApi.default_api_version(api: tool.api),
        params: ActionController::Parameters.new(params_for(tool, arguments)).permit!,
        request_params: empty_request_params, scoped_recordings: access_grant.accessible_recordings
      }
    end

    def empty_request_params
      # GET carries no body. Show reads the metric query from params.
      ActionController::Parameters.new.permit!
    end
    private_class_method :tools_for, :metric_tool_for, :each_argument, :argument_hash, :assign_argument,
                         :assign_filter, :fold_filter, :filter_value, :assign_passthrough, :operation_context,
                         :metric_context, :empty_request_params
  end
end
