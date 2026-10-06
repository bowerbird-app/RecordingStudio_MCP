# frozen_string_literal: true

module RecordingStudioMcp
  module JsonObjectSchema
    module_function

    def valid?(schema, value)
      error_for(schema, value).nil?
    end

    def error_for(schema, value)
      schema = stringify(schema)
      return "arguments must be an object" unless value.is_a?(Hash)

      object = stringify(value)
      return "unexpected argument" if extra_properties?(schema, object)

      missing = Array(schema["required"]).map(&:to_s) - object.keys
      return "missing #{missing.first}" if missing.any?

      object.each do |name, entry|
        expected = property_type(schema, name)
        return "invalid #{name}" unless type_match?(expected, entry)
      end

      nil
    end

    def stringify(value)
      value.transform_keys(&:to_s)
    end
    private_class_method :stringify

    def extra_properties?(schema, object)
      return false unless schema["additionalProperties"] == false

      allowed = (schema["properties"] || {}).keys.map(&:to_s)
      (object.keys - allowed).any?
    end
    private_class_method :extra_properties?

    def property_type(schema, name)
      properties = schema["properties"] || {}
      definition = properties[name] || {}
      definition["type"]
    end
    private_class_method :property_type

    def type_match?(expected, value)
      case expected
      when "string" then value.is_a?(String) && value.present?
      when "integer" then value.is_a?(Integer)
      when "number" then value.is_a?(Numeric)
      when "boolean" then [true, false].include?(value)
      when "object" then value.is_a?(Hash)
      when "array" then value.is_a?(Array)
      when nil then true
      else false
      end
    end
    private_class_method :type_match?
  end
end
