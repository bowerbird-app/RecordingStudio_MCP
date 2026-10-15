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
          period_aliases(name).each { |alias_name| add_period_alias(alias_name, name) }
        end

        def add_period_alias(alias_name, catalog_name)
          @properties[alias_name.to_sym] = {
            type: "string",
            format: "date-time",
            description: "Same as #{period_primary(catalog_name)}."
          }
          @passthrough << alias_name
        end

        def period_primary(name)
          pair = RecordingStudioApi::Metrics::Period::NAMES.find do |_primary, names|
            names.map(&:to_s).include?(name)
          end
          (pair&.first || name).to_s
        end

        def period_aliases(name)
          RecordingStudioApi::Metrics::Period::NAMES.each_value do |names|
            strings = names.map(&:to_s)
            next unless strings.include?(name)

            return strings - [name]
          end
          []
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
  end
end

require "recording_studio_mcp/recordable_metric_tools/registered_entry"
require "recording_studio_mcp/recordable_metric_tools/listing"
require "recording_studio_mcp/recordable_metric_tools/arguments"
require "recording_studio_mcp/recordable_metric_tools/execution"
