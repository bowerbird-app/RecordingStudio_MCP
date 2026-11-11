# frozen_string_literal: true

require_relative "tool_docs/output"
require_relative "tool_docs/endpoint"
require_relative "tool_docs/listing"

module RecordingStudioMcp
  module ToolDocs
    CORE_TAG = "Core"
    TYPES_TAG = "Types"
    CORE_GROUP = "Core"
    ENDPOINTS_GROUP = "Endpoints"
    METRICS_GROUP = "Metrics"
    TYPES_GROUP = "Types"
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

    def metric_group(name)
      name.to_s.split("-", 2).first.to_s
    end

    def humanize_metric_group(prefix)
      prefix.to_s.split("_").map { |part| humanize_part(part) }.join(" ")
    end

    def tag_groups(surface, types:)
      groups = []
      add_group(groups, CORE_GROUP, surface.tags_for(:tree))
      add_group(groups, ENDPOINTS_GROUP, surface.tags_for(:endpoint))
      add_group(groups, METRICS_GROUP, surface.tags_for(:metric))
      add_group(groups, TYPES_GROUP, [TYPES_TAG]) if Array(types).any?
      groups
    end

    def openapi_tags(groups)
      Array(groups).flat_map { |group| Array(group["tags"]) }.uniq.map do |name|
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

    def humanize_part(part)
      return "OAuth" if part.casecmp("oauth").zero?

      upper = part.upcase
      ACRONYMS.include?(upper) ? upper : part.capitalize
    end
    private_class_method :humanize_part

    def add_group(groups, name, tags)
      names = Array(tags).map(&:to_s).reject(&:blank?).uniq
      return if names.empty?

      groups << {
        "name" => name,
        "tags" => names
      }
    end
    private_class_method :add_group
  end
end
