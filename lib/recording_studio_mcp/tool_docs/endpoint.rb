# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module Endpoint
      module_function

      def output_schema(endpoint)
        responses = responses_hash(endpoint)
        return unless responses

        success_status_texts(responses).each do |status|
          schema = json_object_schema(lookup(responses, status))
          return schema if schema
        end
        nil
      end

      def responses_hash(endpoint)
        openapi = endpoint.openapi || {}
        responses = openapi[:responses] || openapi["responses"]
        responses if responses.is_a?(Hash)
      end
      private_class_method :responses_hash

      def success_status_texts(responses)
        texts = responses.keys.map(&:to_s)
        two_hundred = texts.select { |text| text == "200" }
        other = texts.select { |text| text.match?(/\A2\d\d\z/) && text != "200" }.sort
        wildcard = texts.select { |text| text.casecmp("2XX").zero? }
        two_hundred + other + wildcard
      end
      private_class_method :success_status_texts

      def lookup(responses, status)
        responses[status] || responses[status.to_sym]
      end
      private_class_method :lookup

      def json_object_schema(response)
        schema = application_json_schema(response)
        return unless schema.is_a?(Hash)
        return if ref_only?(schema)
        return unless object_type?(schema)

        schema
      end
      private_class_method :json_object_schema

      def application_json_schema(response)
        return unless response.is_a?(Hash)

        content = response[:content] || response["content"]
        return unless content.is_a?(Hash)

        json = content[:"application/json"] || content["application/json"]
        return unless json.is_a?(Hash)

        json[:schema] || json["schema"]
      end
      private_class_method :application_json_schema

      def ref_only?(schema)
        schema.key?("$ref") || schema.key?(:$ref)
      end
      private_class_method :ref_only?

      def object_type?(schema)
        type = schema[:type] || schema["type"]
        type.to_s == "object"
      end
      private_class_method :object_type?
    end
  end
end
