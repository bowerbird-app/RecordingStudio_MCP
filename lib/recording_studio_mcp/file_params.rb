# frozen_string_literal: true

module RecordingStudioMcp
  module FileParams
    OPENAPI_KEY = :"x-mcp-file-params"
    FILE_PROPERTIES = {
      download_url: { type: "string", description: "Temporary URL to download the file." },
      file_id: { type: "string", description: "File id." },
      mime_type: { type: "string" },
      file_name: { type: "string" }
    }.freeze
    FILE_REQUIRED = %w[download_url file_id].freeze
    META_KEY = "openai/fileParams"
    REDACTED = "[redacted]"

    module_function

    def fields(endpoint)
      declared = endpoint.openapi.is_a?(Hash) ? endpoint.openapi[OPENAPI_KEY] : nil
      fields = case declared
               when Array then declared.to_h { |name| [name.to_s, normalize({})] }
               when Hash then declared.to_h { |name, options| [name.to_s, normalize(options)] }
               else {}
               end
      fields.except(*path_tokens(endpoint))
    end

    def path_tokens(endpoint)
      endpoint.path_segments.filter_map { |segment| segment.delete_prefix(":") if segment.start_with?(":") }
    end

    def names(endpoint)
      fields(endpoint).keys
    end

    def apply(schema, endpoint)
      declared = fields(endpoint)
      return schema if declared.empty?

      files = declared.to_h { |name, options| [name.to_sym, property(options)] }
      required = declared.select { |_name, options| options[:required] }.keys
      schema.merge(
        properties: schema.fetch(:properties).merge(files),
        required: (schema.fetch(:required) + required).uniq
      )
    end

    def property(options)
      schema = {
        type: options[:nullable] ? %w[object null] : "object",
        properties: FILE_PROPERTIES.deep_dup,
        required: FILE_REQUIRED.dup
      }
      schema[:description] = options[:description] if options[:description].present?
      schema
    end

    def normalize(options)
      options = options.respond_to?(:to_h) ? options.to_h.symbolize_keys : {}
      {
        nullable: options[:nullable] == true,
        required: options[:required] == true,
        description: options[:description].presence
      }
    end

    def ensure_file_schema(schema)
      return schema unless file_schema?(schema)
      return schema if schema[:required].is_a?(Array) || schema["required"].is_a?(Array)

      schema[:required] = FILE_REQUIRED.dup
      schema
    end

    def annotate(payload)
      names = field_names(payload.dig(:inputSchema, :properties))
      return payload if names.empty?

      payload[:_meta] = (payload[:_meta] || {}).merge(META_KEY => names)
      payload
    end

    def field_names(properties)
      return [] unless properties.is_a?(Hash)

      properties.filter_map { |name, schema| name.to_s if file_schema?(schema) }
    end

    def file_schema?(schema)
      return false unless schema.is_a?(Hash)
      return false unless object_type?(schema[:type] || schema["type"])

      names = property_names(schema)
      names.include?("download_url") && names.include?("file_id")
    end

    def object_type?(type)
      types = type.is_a?(Array) ? type : [type]
      types.map(&:to_s).include?("object")
    end

    def property_names(schema)
      properties = schema[:properties] || schema["properties"]
      return [] unless properties.is_a?(Hash)

      properties.keys.map(&:to_s)
    end
    private_class_method :file_schema?, :object_type?, :property_names
  end
end

require_relative "file_params/redaction"
