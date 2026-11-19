# frozen_string_literal: true

module RecordingStudioMcp
  module SchemaFromContract
    TYPE_MAP = {
      "string" => "string",
      "integer" => "integer",
      "float" => "number",
      "number" => "number",
      "boolean" => "boolean",
      "array" => "array",
      "hash" => "object",
      "object" => "object",
      "symbol" => "string"
    }.freeze
    PROTOCOL_KEYS = %w[
      type id parent_id q limit sort order filter pagination_token action params idempotency_key
    ].freeze
    NESTED_SCHEMA_KEYS = %i[items properties additionalProperties].freeze

    module_function

    def json_type(contract_field)
      TYPE_MAP.fetch(field_value(contract_field, :type).to_s, "string")
    end

    def required?(contract_field)
      field_value(contract_field, :required) == true
    end

    def allow_blank?(contract_field)
      value = field_value(contract_field, :allow_blank)
      value.nil? ? !required?(contract_field) : value != false
    end

    def property(contract_field, copy: {})
      json = json_type(contract_field)
      built = { type: json }
      overlay_copy_on(built, copy)
      enum = field_value(contract_field, :enum)
      built[:enum] = Array(enum) if enum.present?
      built[:minLength] = 1 if json == "string" && !allow_blank?(contract_field)
      attach_nested_schema(built, contract_field)
      built
    end

    def properties(contract, copy: {})
      stringify(contract).to_h do |name, field|
        [name.to_sym, property(field, copy: copy[name] || {})]
      end
    end

    def required_names(contract)
      stringify(contract).each_with_object([]) do |(name, field), names|
        names << name if required?(field)
      end
    end

    def overlay_copy(properties, copy)
      copy.to_h.each do |name, meta|
        key = name.to_sym
        next unless properties[key]

        properties[key] = properties[key].dup
        overlay_copy_on(properties[key], meta)
      end
      properties
    end

    def overlay_tool(definition, title:, description:)
      overlaid = definition.dup
      overlaid[:title] = title if title.present?
      overlaid[:description] = description if description.present?
      overlaid
    end

    def stringify(contract)
      return {} if contract.blank?

      contract.to_h.transform_keys(&:to_s)
    end

    def field_value(field, key)
      return unless field.respond_to?(:[])

      field[key] || field[key.to_s]
    end

    def overlay_copy_on(property, copy)
      meta = copy.to_h.transform_keys(&:to_sym)
      property[:description] = meta[:description] if meta[:description].present?
      property[:examples] = Array(meta[:example]) if meta.key?(:example)
    end

    def attach_nested_schema(built, contract_field)
      NESTED_SCHEMA_KEYS.each do |key|
        value = field_value(contract_field, key)
        next if value.nil?

        built[key] = json_schema_fragment(value)
      end
    end

    def json_schema_fragment(value)
      case value
      when Hash
        value.to_h.each_with_object({}) do |(key, entry), copy|
          copy[key.to_sym] = json_schema_fragment(entry)
        end
      when Array
        value.map { |entry| json_schema_fragment(entry) }
      else
        value
      end
    end
    private_class_method :overlay_copy_on, :attach_nested_schema, :json_schema_fragment
  end
end
