# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
    FROM = RegisteredEntry::FROM
    TO = RegisteredEntry::TO
    GROUP = RegisteredEntry::GROUP
    FILTERS = "Metric filters. The metric reads this as params[:filters]."

    module_function

    def collect_catalog(catalog, access_grant)
      tools = catalog_entries(catalog, access_grant).filter_map { |entry| catalog_tool_for(catalog, entry) }
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

    def catalog_tool_for(catalog, entry)
      identifier = read_key(entry, :identifier).to_s
      Tool.new(**catalog_tool_fields(catalog, entry, identifier))
    rescue StandardError
      warn_skipped(identifier)
      nil
    end

    def catalog_tool_fields(catalog, entry, identifier)
      resource = read_key(entry, :resource)
      {
        name: ToolName.from_identifier(identifier), identifier: identifier, kind: :catalog,
        resource: resource, resource_name: resource, recordable_type: nil, metric_name: read_key(entry, :name),
        api: catalog.api, description: read_key(entry, :description),
        title: read_key(entry, :title).presence || read_key(entry, :name).to_s,
        plan: ArgumentPlan.from(parameters_for(entry))
      }
    end

    def read_key(entry, key)
      return if entry.nil?

      entry[key].nil? ? entry[key.to_s] : entry[key]
    end

    def grant_value(grant, name)
      grant.public_send(name) if grant.respond_to?(name)
    end
    private_class_method :catalog_entries, :resource_allowed?, :catalog_tool_for, :catalog_tool_fields, :read_key,
                         :grant_value
  end
end

require "recording_studio_mcp/metric_tools/catalog/discovery"
require "recording_studio_mcp/metric_tools/catalog/schema"
require "recording_studio_mcp/metric_tools/catalog/execution"
