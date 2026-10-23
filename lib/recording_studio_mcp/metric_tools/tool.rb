# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
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
      :name, :metric_name, :api, :description, :plan, :kind,
      :recordable_type, :resource_name, :resource, :identifier, :title
    ) do
      def initialize(**fields)
        super(**freeze_fields(checked_fields(fields)))
      end

      def catalog?
        kind == :catalog
      end

      def display_title
        title.presence || metric_name.to_s.tr("._", " ").capitalize
      end

      def definition_options
        {
          name: name.to_s, title: display_title, description: description.presence || display_title,
          read_only: true, destructive: false, idempotent: true,
          required: plan.required, properties: plan.properties,
          additional_properties: false, api: api
        }
      end

      private

      def checked_fields(fields)
        name = fields.fetch(:name)
        plan = fields.fetch(:plan)
        kind = fields.fetch(:kind).to_sym
        metric_name = fields.fetch(:metric_name).to_s
        identifier = (fields[:identifier] || metric_name).to_s
        check_tool_shape!(name, plan, kind, identifier)
        fields.merge(name: name, plan: plan, kind: kind, metric_name: metric_name, identifier: identifier)
      end

      def check_tool_shape!(name, plan, kind, identifier)
        raise ArgumentError, "Metric tool name must be a ToolName" unless name.is_a?(ToolName)
        raise ArgumentError, "Metric tool plan must be an ArgumentPlan" unless plan.is_a?(ArgumentPlan)
        unless %i[recordable catalog].include?(kind)
          raise ArgumentError, "Metric tool kind must be :recordable or :catalog"
        end
        return if name == ToolName.from_identifier(identifier)

        raise RecordingStudioApi::ConfigurationError, "Metric tool name #{name} does not match #{identifier}"
      end

      def freeze_fields(fields)
        frozen = %i[metric_name api recordable_type resource_name resource identifier].to_h do |key|
          [key, fields.fetch(key) { fields[key] }.to_s.freeze]
        end
        frozen[:description] = fields[:description]&.to_s&.freeze
        frozen[:title] = fields[:title]&.to_s&.freeze
        fields.merge(frozen)
      end
    end
  end
end
