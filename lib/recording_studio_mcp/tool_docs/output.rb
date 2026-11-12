# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module Output
      RECORD_KEYS = %w[id type parent_id root_id].freeze
      LIST_META = {
        type: "object",
        properties: { next_pagination_token: { type: "string" } },
        additionalProperties: true
      }.freeze
      DELETE = {
        type: "object",
        properties: { deleted: { type: "boolean" }, id: { type: "string" } },
        additionalProperties: true
      }.freeze
      ACTION = { type: "object", additionalProperties: true }.freeze
      CAPABILITY_ACTION = {
        type: "object",
        properties: {
          name: { type: "string" },
          title: { type: "string" },
          summary: { type: "string" },
          description: { type: "string" },
          params: ACTION
        },
        additionalProperties: true
      }.freeze
      DESCRIBE_PROPERTIES = {
        type: { type: "string" },
        description: { type: "string" },
        operations: { type: "array", items: { type: "string" } },
        writable_fields: { type: "array", items: ACTION },
        capability_actions: { type: "array", items: CAPABILITY_ACTION },
        output_keys: { type: "array", items: { type: "string" } },
        fields: { type: "array", items: { type: "string" } },
        relationships: { type: "array", items: ACTION },
        allowed_children: { type: "array", items: { type: "string" } },
        parent: ACTION
      }.freeze
      METRIC_POINT = {
        type: "object",
        properties: { date: { type: "string" }, value: { type: "number" } },
        additionalProperties: true
      }.freeze
      METRIC_PROPERTIES = {
        value: { type: "number" },
        metric: { type: "string" },
        data: { type: "array", items: METRIC_POINT },
        metrics: { type: "array", items: ACTION }
      }.freeze

      module_function

      def list(catalog)
        object(
          properties: {
            records: { type: "array", items: record(catalog) },
            meta: LIST_META
          },
          required: ["records"]
        )
      end

      def record(catalog)
        properties = RECORD_KEYS.index_with { { type: "string" } }
        properties["root_id"] = { type: "string", description: "Workspace id, not the parent record." }
        extra_keys(catalog).each { |key| properties[key] ||= { type: "string" } }
        object(properties: properties)
      end

      def delete
        DELETE
      end

      def describe
        object(properties: DESCRIBE_PROPERTIES)
      end

      def action
        ACTION
      end

      def metric
        object(properties: METRIC_PROPERTIES)
      end

      def object(properties:, required: nil)
        schema = { type: "object", properties: properties, additionalProperties: true }
        schema[:required] = required if required
        schema
      end
      private_class_method :object

      def extra_keys(catalog)
        return Array(catalog.union_output_keys).map(&:to_s) if catalog.respond_to?(:union_output_keys)

        []
      end
      private_class_method :extra_keys
    end
  end
end
