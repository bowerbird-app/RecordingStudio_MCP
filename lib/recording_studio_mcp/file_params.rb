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
  end
end
