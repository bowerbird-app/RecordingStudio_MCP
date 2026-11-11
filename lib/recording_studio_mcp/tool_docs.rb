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

    def type_tags(type_name, api:)
      registration = RecordingStudioApi.recordable_registration_for(type_name, api: api)
      registered_openapi_tags(registration).presence ||
        endpoint_tags_for_type_group(registration, api: api)
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
      Array(source&.openapi&.[](:tags)).map(&:to_s).reject(&:blank?).uniq
    end
    private_class_method :registered_openapi_tags

    def endpoint_tags_for_type_group(registration, api:)
      group = registration&.openapi&.dig(:tag, :group)
      return [] if group.blank?

      Catalog.new(api: api).registered_endpoints.flat_map do |endpoint|
        next [] unless endpoint.openapi&.dig(:tag, :group).to_s == group.to_s

        registered_openapi_tags(endpoint)
      end.uniq
    end
    private_class_method :endpoint_tags_for_type_group

    def humanize_part(part)
      return "OAuth" if part.casecmp("oauth").zero?

      upper = part.upcase
      ACRONYMS.include?(upper) ? upper : part.capitalize
    end
    private_class_method :humanize_part
  end
end
