# frozen_string_literal: true

require_relative "tool_docs/output"
require_relative "tool_docs/endpoint"
require_relative "tool_docs/listing"

module RecordingStudioMcp
  module ToolDocs
    CORE_TAG = "Core"
    ACRONYMS = %w[AI API CSRF CSS HTML HTTP HTTPS ID JSON MCP SSE UI URL].freeze

    module_function

    def tree_tags
      [CORE_TAG]
    end

    def metric_tags(name)
      [humanize_metric_group(metric_group(name))]
    end

    def endpoint_tags(endpoint)
      Array(endpoint.openapi_tags).map(&:to_s).reject(&:blank?).presence ||
        [RecordingStudioApi::RegisteredEndpoint::DEFAULT_OPENAPI_TAG]
    end

    def type_tags(type_name, api:, group_tags: nil)
      registration = RecordingStudioApi.recordable_registration_for(type_name, api: api)
      tags = registered_openapi_tags(registration)
      return tags if tags.any?

      group = registration&.openapi&.dig(:tag, :group)
      return [] if group.blank?

      Array((group_tags || endpoint_group_tags(api: api))[group.to_s])
    end

    def action_tags(type_name, api:, group_tags: nil, type_names: [])
      tags = type_tags(type_name, api: api, group_tags: group_tags)
      return tags if tags.any?

      namespaced_action_tags(type_name, api: api, group_tags: group_tags, type_names: type_names)
    end

    def endpoint_group_tags(api:)
      Catalog.new(api: api).registered_endpoints.each_with_object({}) do |endpoint, acc|
        group = endpoint.openapi&.dig(:tag, :group)
        next if group.blank?

        names = registered_openapi_tags(endpoint)
        next if names.empty?

        key = group.to_s
        acc[key] = (Array(acc[key]) + names).uniq
      end
    end

    def metric_group(name)
      name.to_s.split("-", 2).first.to_s
    end

    def humanize_metric_group(prefix)
      prefix.to_s.split("_").map { |part| humanize_part(part) }.join(" ")
    end

    def openapi_tags(names)
      Array(names).map(&:to_s).reject(&:blank?).uniq.map do |name|
        { "name" => name }
      end
    end

    def list_output_schema(catalog)
      Output.list(catalog)
    end

    def record_output_schema(catalog)
      Output.record(catalog)
    end

    def delete_output_schema
      Output.delete
    end

    def describe_output_schema
      Output.describe
    end

    def action_output_schema
      Output.action
    end

    def metric_output_schema
      Output.metric
    end

    def endpoint_output_schema(endpoint)
      Endpoint.output_schema(endpoint)
    end

    def registered_openapi_tags(source)
      openapi_tags(source&.openapi&.[](:tags)).map { |tag| tag["name"] }
    end
    private_class_method :registered_openapi_tags

    def namespaced_action_tags(type_name, api:, group_tags:, type_names:)
      prefix = type_name.to_s.deconstantize
      return [] if prefix.blank?

      Array(type_names).flat_map do |other|
        next [] if other.to_s == type_name.to_s
        next [] unless other.to_s.start_with?("#{prefix}::")

        type_tags(other, api: api, group_tags: group_tags)
      end.uniq
    end
    private_class_method :namespaced_action_tags

    def humanize_part(part)
      return "OAuth" if part.casecmp("oauth").zero?

      upper = part.upcase
      ACRONYMS.include?(upper) ? upper : part.capitalize
    end
    private_class_method :humanize_part
  end
end
