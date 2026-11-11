# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module Endpoint
      module_function

      def output_schema(endpoint)
        openapi = endpoint.openapi || {}
        responses = openapi[:responses] || openapi["responses"]
        return unless responses.is_a?(Hash)

        first_success_schema(responses)
      end

      def first_success_schema(responses)
        ranked_keys(responses).each do |key|
          schema = schema_from_response(responses[key] || responses[key.to_s] || responses[key.to_sym])
          return schema if schema.is_a?(Hash)
        end
        nil
      end
      private_class_method :first_success_schema

      def ranked_keys(responses)
        responses.keys.sort_by { |key| success_rank(key) }
      end
      private_class_method :ranked_keys

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

        schema_from_json_content(response[:content] || response["content"]) ||
          response[:schema] || response["schema"]
      end
      private_class_method :schema_from_response

      def schema_from_json_content(content)
        return unless content.is_a?(Hash)

        json = content[:"application/json"] || content["application/json"]
        json[:schema] || json["schema"] if json.is_a?(Hash)
      end
      private_class_method :schema_from_json_content
    end
  end
end
