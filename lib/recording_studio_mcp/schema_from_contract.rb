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

    module_function

    def json_type(contract_field)
      raw = field_value(contract_field, :type)
      TYPE_MAP.fetch(raw.to_s, "string")
    end

    def required?(contract_field)
      field_value(contract_field, :required) == true
    end

    def allow_blank?(contract_field)
      value = field_value(contract_field, :allow_blank)
      value.nil? ? !required?(contract_field) : value != false
    end

    def property(contract_field, copy:)
      property = { type: json_type(contract_field) }
      property[:description] = copy[:description] if copy[:description].present?
      property[:examples] = Array(copy[:example]) if copy.key?(:example)
      enum = field_value(contract_field, :enum) || copy[:enum]
      property[:enum] = Array(enum) if enum.present?
      property[:minLength] = 1 if property[:type] == "string" && !allow_blank?(contract_field)
      property
    end

    def required_names(contract)
      contract.each_with_object([]) do |(name, field), names|
        names << name.to_s if required?(field)
      end
    end

    def field_value(field, key)
      return unless field.respond_to?(:[])

      field[key] || field[key.to_s]
    end
  end
end
