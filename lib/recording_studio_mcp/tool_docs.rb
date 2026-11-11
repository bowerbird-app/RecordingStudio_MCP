# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    CORE_TAG = "Core"
    TYPES_TAG = "Types"
    CORE_GROUP = "Core"
    ENDPOINTS_GROUP = "Endpoints"
    METRICS_GROUP = "Metrics"
    TYPES_GROUP = "Types"
    ACRONYMS = %w[AI API CSRF CSS HTML HTTP HTTPS ID JSON MCP SSE UI URL].freeze
    RECORD_KEYS = %w[id type parent_id root_id].freeze

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
      Array(groups).flat_map { |group| Array(group["tags"]) }.uniq.map { |name| { "name" => name } }
    end

    def list_output_schema(catalog)
      {
        type: "object",
        properties: {
          records: { type: "array", items: record_output_schema(catalog) },
          meta: {
            type: "object",
            properties: {
              next_pagination_token: { type: "string" }
            },
            additionalProperties: true
          }
        },
        required: ["records"],
        additionalProperties: true
      }
    end

    def record_output_schema(catalog)
      properties = RECORD_KEYS.index_with { |key| { type: "string" } }
      properties["root_id"] = { type: "string", description: "Workspace id, not the parent record." }
      output_keys_from(catalog).each do |key|
        properties[key] ||= { type: "string" }
      end
      { type: "object", properties: properties, additionalProperties: true }
    end

    def delete_output_schema
      {
        type: "object",
        properties: {
          deleted: { type: "boolean" },
          id: { type: "string" }
        },
        additionalProperties: true
      }
    end

    def describe_output_schema
      {
        type: "object",
        properties: {
          type: { type: "string" },
          operations: { type: "array", items: { type: "string" } },
          writable_fields: { type: "array", items: { type: "object", additionalProperties: true } },
          capability_actions: { type: "array", items: { type: "object", additionalProperties: true } },
          output_keys: { type: "array", items: { type: "string" } },
          fields: { type: "array", items: { type: "string" } },
          relationships: { type: "array", items: { type: "object", additionalProperties: true } },
          allowed_children: { type: "array", items: { type: "string" } },
          parent: { type: "object", additionalProperties: true }
        },
        additionalProperties: true
      }
    end

    def action_output_schema
      { type: "object", additionalProperties: true }
    end

    def metric_output_schema
      {
        type: "object",
        properties: {
          value: { type: "number" },
          metric: { type: "string" },
          data: {
            type: "array",
            items: {
              type: "object",
              properties: {
                date: { type: "string" },
                value: { type: "number" }
              },
              additionalProperties: true
            }
          },
          metrics: { type: "array", items: { type: "object", additionalProperties: true } }
        },
        additionalProperties: true
      }
    end

    def endpoint_output_schema(endpoint)
      openapi = endpoint.openapi || {}
      responses = openapi[:responses] || openapi["responses"]
      return unless responses.is_a?(Hash)

      json_schema_from_responses(responses)
    end

    def output_keys_from(catalog)
      return Array(catalog.union_output_keys).map(&:to_s) if catalog.respond_to?(:union_output_keys)

      []
    end
    private_class_method :output_keys_from

    def humanize_part(part)
      return "OAuth" if part.casecmp("oauth").zero?

      upper = part.upcase
      ACRONYMS.include?(upper) ? upper : part.capitalize
    end
    private_class_method :humanize_part

    def add_group(groups, name, tags)
      names = Array(tags).map(&:to_s).reject(&:blank?).uniq
      return if names.empty?

      groups << { "name" => name, "tags" => names }
    end
    private_class_method :add_group

    def json_schema_from_responses(responses)
      ranked_response_keys(responses).each do |key|
        schema = schema_from_response(responses[key] || responses[key.to_s] || responses[key.to_sym])
        return schema if schema.is_a?(Hash)
      end
      nil
    end
    private_class_method :json_schema_from_responses

    def ranked_response_keys(responses)
      responses.keys.sort_by { |key| success_rank(key) }
    end
    private_class_method :ranked_response_keys

    def success_rank(key)
      text = key.to_s
      return 0 if text == "200"
      return 1 if text.match?(/\A2\d\d\z/)
      return 2 if text.casecmp("2XX").zero?
      return 3 if text == "default"

      99
    end
    private_class_method :success_rank

    def schema_from_response(response)
      return unless response.is_a?(Hash)

      content = response[:content] || response["content"]
      schema = schema_from_json_content(content)
      schema || response[:schema] || response["schema"]
    end
    private_class_method :schema_from_response

    def schema_from_json_content(content)
      return unless content.is_a?(Hash)

      json = content[:"application/json"] || content["application/json"]
      return unless json.is_a?(Hash)

      json[:schema] || json["schema"]
    end
    private_class_method :schema_from_json_content
  end
end
