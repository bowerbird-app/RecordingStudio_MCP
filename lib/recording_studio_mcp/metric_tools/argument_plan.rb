# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
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
