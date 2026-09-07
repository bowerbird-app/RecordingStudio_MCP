# frozen_string_literal: true

module RecordingStudioMcp
  class FieldSchema
    TYPE_MAP = {
      bigint: "integer",
      binary: "string",
      boolean: "boolean",
      date: "string",
      datetime: "string",
      decimal: "number",
      float: "number",
      integer: "integer",
      json: "object",
      jsonb: "object",
      string: "string",
      text: "string",
      time: "string"
    }.freeze

    def self.for(recordable_type, registration)
      new(recordable_type, registration).fields
    end

    def initialize(recordable_type, registration)
      @recordable_class = recordable_type.to_s.safe_constantize
      @registration = registration
    end

    def fields
      Array(registration&.writable_attributes).map do |field_name|
        field(field_name.to_s)
      end
    end

    private

    attr_reader :recordable_class, :registration

    def field(name)
      property = openapi_properties[name] || {}
      {
        "name" => name,
        "required" => required?(name),
        "type" => property_value(property, :type) || column_type(name),
        "allowed_values" => allowed_values(name, property),
        "description" => property_value(property, :description).presence,
        "immutable_on_update" => immutable?(name) || nil
      }.compact
    end

    def openapi_properties
      @openapi_properties ||= (details_schema[:properties] || details_schema["properties"] || {})
                              .to_h.transform_keys(&:to_s)
    end

    def openapi_required
      @openapi_required ||= Array(details_schema[:required] || details_schema["required"]).map(&:to_s)
    end

    def details_schema
      @details_schema ||= openapi_details_schema || {}
    end

    def openapi_details_schema
      openapi = registration&.openapi
      openapi[:details_schema] || openapi["details_schema"] if openapi
    end

    def property_value(property, key)
      property[key] || property[key.to_s]
    end

    def required?(name)
      return true if openapi_required.include?(name)
      return false unless recordable_class.respond_to?(:validators_on)

      unconditional_presence?(name) || required_column?(name)
    end

    def unconditional_presence?(name)
      recordable_class.validators_on(name).any? do |validator|
        validator.kind == :presence &&
          validator.options[:on].in?([nil, :create, :save]) &&
          validator.options[:if].blank? &&
          validator.options[:unless].blank?
      end
    end

    def required_column?(name)
      column = recordable_class.columns_hash[name] if recordable_class.respond_to?(:columns_hash)
      column.present? && !column.null && column.default.nil?
    end

    def column_type(name)
      column = recordable_class.columns_hash[name] if recordable_class.respond_to?(:columns_hash)
      TYPE_MAP.fetch(column&.type, "string")
    end

    def allowed_values(name, property)
      values = property_value(property, :enum) || enum_values(name) || inclusion_values(name)
      Array(values).presence
    end

    def enum_values(name)
      return unless recordable_class.respond_to?(:defined_enums)

      recordable_class.defined_enums[name]&.keys
    end

    def inclusion_values(name)
      return unless recordable_class.respond_to?(:validators_on)

      validator = recordable_class.validators_on(name).find { |entry| entry.kind == :inclusion }
      values = validator&.options&.fetch(:in, nil)
      values.to_a if values.is_a?(Array) || values.is_a?(Range)
    end

    def immutable?(name)
      Array(registration&.immutable_fields).map(&:to_s).include?(name)
    end
  end
end
