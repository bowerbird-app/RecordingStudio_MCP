# frozen_string_literal: true

module RecordingStudioMcp
  module CatalogMetricTools
    FROM = RecordableMetricTools::RegisteredEntry::FROM
    TO = RecordableMetricTools::RegisteredEntry::TO
    GROUP = RecordableMetricTools::RegisteredEntry::GROUP
    FILTERS = "Metric filters. The metric reads this as params[:filters]."

    Tool = Data.define(
      :name, :identifier, :resource, :metric_name, :api, :description, :plan, :title
    ) do
      def initialize(**fields)
        super(**freeze_fields(checked_fields(fields)))
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
        identifier = fields.fetch(:identifier).to_s
        assert_shape!(name, plan, identifier)
        fields.merge(name: name, plan: plan, identifier: identifier)
      end

      def assert_shape!(name, plan, identifier)
        raise ArgumentError, "Metric tool name must be a ToolName" unless name.is_a?(RecordableMetricTools::ToolName)
        unless plan.is_a?(RecordableMetricTools::ArgumentPlan)
          raise ArgumentError, "Metric tool plan must be an ArgumentPlan"
        end
        return if name == RecordableMetricTools::ToolName.from_identifier(identifier)

        raise RecordingStudioApi::ConfigurationError, "Metric tool name #{name} does not match #{identifier}"
      end

      def freeze_fields(fields)
        frozen = fields.merge(description: fields[:description]&.to_s&.freeze)
        %i[identifier resource metric_name api title].each do |key|
          frozen[key] = frozen.fetch(key).to_s.freeze
        end
        frozen
      end
    end

    module_function

    def collect(catalog, access_grant)
      tools = catalog_entries(catalog, access_grant).filter_map { |entry| tool_for(catalog, entry) }
      tools.sort_by { |tool| tool.name.to_s }.freeze
    end

    def catalog_entries(catalog, access_grant)
      raw_entries(catalog, access_grant).select { |entry| resource_allowed?(read_key(entry, :resource)) }
    end

    def resource_allowed?(resource)
      allowlist = RecordingStudioMcp.configuration.catalog_metric_resources
      return true if allowlist.nil?

      allowlist.include?(resource.to_s)
    end

    def tool_for(catalog, entry)
      identifier = read_key(entry, :identifier).to_s
      Tool.new(**tool_fields(catalog, entry, identifier))
    rescue StandardError
      warn_skipped(identifier)
      nil
    end

    def tool_fields(catalog, entry, identifier)
      {
        name: RecordableMetricTools::ToolName.from_identifier(identifier),
        identifier: identifier,
        resource: read_key(entry, :resource),
        metric_name: read_key(entry, :name),
        api: catalog.api,
        description: read_key(entry, :description),
        title: read_key(entry, :title).presence || read_key(entry, :name).to_s,
        plan: RecordableMetricTools::ArgumentPlan.from(parameters_for(entry))
      }
    end

    def read_key(entry, key)
      return if entry.nil?

      entry[key].nil? ? entry[key.to_s] : entry[key]
    end

    def grant_value(grant, name)
      grant.public_send(name) if grant.respond_to?(name)
    end

    def warn_skipped(name)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[RecordingStudioMcp] skipped catalog metric #{name}")
    end
    private_class_method :catalog_entries, :resource_allowed?, :tool_for, :tool_fields, :read_key, :grant_value,
                         :warn_skipped
  end
end

require "recording_studio_mcp/catalog_metric_tools/discovery"
require "recording_studio_mcp/catalog_metric_tools/schema"
require "recording_studio_mcp/catalog_metric_tools/execution"
