# frozen_string_literal: true

module OutputSchemaCheck
  module_function

  def errors(schema, value, path = "$")
    schema = stringify(schema)
    return ["#{path} schema must be an object"] unless schema.is_a?(Hash)

    type = schema["type"].to_s
    case type
    when "object" then object_errors(schema, value, path)
    when "array" then array_errors(schema, value, path)
    when "" then enum_errors(schema, value, path)
    else scalar_errors(schema, value, path)
    end
  end

  def stringify(value)
    return value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)
    return value.transform_keys(&:to_s) if value.is_a?(Hash)

    value
  end
  private_class_method :stringify

  def object_errors(schema, value, path)
    return ["#{path} must be an object"] unless value.is_a?(Hash)

    object = stringify(value)
    problems = []
    Array(schema["required"]).each do |name|
      problems << "#{path}.#{name} is required" unless object.key?(name.to_s)
    end
    properties = stringify(schema["properties"] || {})
    extra_allowed = schema["additionalProperties"] != false
    required = Array(schema["required"]).map(&:to_s)
    object.each_key do |name|
      child = object[name]
      next if child.nil? && required.exclude?(name)

      if properties.key?(name)
        problems.concat(errors(properties[name], child, "#{path}.#{name}"))
      elsif !extra_allowed
        problems << "#{path}.#{name} is not allowed"
      end
    end
    problems.concat(enum_errors(schema, object, path))
    problems
  end
  private_class_method :object_errors

  def array_errors(schema, value, path)
    return ["#{path} must be an array"] unless value.is_a?(Array)

    items = schema["items"]
    problems = value.each_with_index.flat_map do |entry, index|
      next [] unless items.is_a?(Hash)

      errors(items, entry, "#{path}[#{index}]")
    end
    problems.concat(enum_errors(schema, value, path))
    problems
  end
  private_class_method :array_errors

  def scalar_errors(schema, value, path)
    expected = schema["type"].to_s
    return ["#{path} must be #{expected}"] unless type_match?(expected, value)

    enum_errors(schema, value, path)
  end
  private_class_method :scalar_errors

  def enum_errors(schema, value, path)
    allowed = schema["enum"]
    return [] unless allowed.is_a?(Array)
    return [] if allowed.map { |entry| stringify(entry) }.include?(stringify(value))

    ["#{path} must be one of #{allowed.inspect}"]
  end
  private_class_method :enum_errors

  def type_match?(expected, value)
    case expected
    when "string" then value.is_a?(String)
    when "integer" then value.is_a?(Integer)
    when "number" then value.is_a?(Numeric)
    when "boolean" then [true, false].include?(value)
    when "object" then value.is_a?(Hash)
    when "array" then value.is_a?(Array)
    else true
    end
  end
  private_class_method :type_match?
end
