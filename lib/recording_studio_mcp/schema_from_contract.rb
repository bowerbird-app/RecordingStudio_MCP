# frozen_string_literal: true

require_relative "nested_schema"
require_relative "file_params"

module RecordingStudioMcp
  module SchemaFromContract
    PROTOCOL_KEYS = %w[
      type id parent_id q limit sort order filter pagination_token action params idempotency_key
    ].freeze
    JSON_TYPES = %w[string integer number boolean array object].freeze

    module_function

    def json_type(contract_field)
      raw = field_value(contract_field, :type)
      name = raw.to_s
      return name if JSON_TYPES.include?(name)

      token = name.presence&.to_sym || :string
      # Invert contract_type_for: JSON schema type whose contract token matches this field.
      JSON_TYPES.find do |json|
        RecordingStudioApi::Services::DocumentationCatalog.contract_type_for(json) == token
      end || "string"
    end

    def required?(contract_field)
      field_value(contract_field, :required) == true
    end

    def allow_blank?(contract_field)
      value = field_value(contract_field, :allow_blank)
      value.nil? ? !required?(contract_field) : value != false
    end

    def properties_for(lookup, recordable_type:, operation:, api:, copy: {})
      contract = stringify(lookup&.input_contract)
      catalog = stringify(attributes_properties(recordable_type, operation, api))
      properties(contract, copy: copy, catalog_properties: catalog)
    end

    def property(contract_field, copy: {}, catalog_property: nil)
      built = catalog_property_schema(catalog_property)
      built[:type] ||= json_type(contract_field)
      fill_nested_object(built, contract_field)
      overlay_copy_on(built, copy)
      fill_contract_description(built, contract_field)
      fill_contract_example(built, contract_field)
      apply_contract_constraints(built, contract_field)
      FileParams.ensure_file_schema(built)
    end

    def properties(contract, copy: {}, catalog_properties: {})
      catalog = stringify(catalog_properties)
      host = stringify(copy)
      stringify(contract).to_h do |name, field|
        [name.to_sym, property(field, copy: host[name] || {}, catalog_property: catalog[name])]
      end
    end

    def required_names(contract)
      stringify(contract).each_with_object([]) do |(name, field), names|
        names << name if required?(field)
      end
    end

    def overlay_copy(properties, copy)
      stringify(copy).each do |name, meta|
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

    def fill_nested_object(built, contract_field)
      NestedSchema.object_fragment(contract_field).each do |key, value|
        built[key] = value unless built.key?(key)
      end
      built[:type] = "object" if built[:properties].is_a?(Hash) && !object_type?(built[:type])
    end

    def object_type?(type)
      types = type.is_a?(Array) ? type : [type]
      types.map(&:to_s).include?("object")
    end

    def fill_contract_description(built, contract_field)
      return if built[:description].present?

      description = field_value(contract_field, :description)
      built[:description] = description.to_s if description.present?
    end

    def fill_contract_example(built, contract_field)
      return if built.key?(:examples)

      example = field_value(contract_field, :example)
      return unless example.is_a?(String) || example.is_a?(Numeric) || example == true || example == false

      built[:examples] = [example]
    end

    def catalog_property_schema(catalog_property)
      return {} if catalog_property.blank?

      NestedSchema.copy(catalog_property).transform_keys(&:to_sym)
    end

    def apply_contract_constraints(built, contract_field)
      enum = field_value(contract_field, :enum)
      built[:enum] = Array(enum) if enum.present? && !built.key?(:enum)
      return unless built[:type].to_s == "string" && !allow_blank?(contract_field) && !built.key?(:minLength)

      built[:minLength] = 1
    end

    def attributes_properties(recordable_type, operation, api)
      schema = RecordingStudioApi::Services::DocumentationCatalog.attributes_schema_for(
        recordable_type,
        mutable: operation.to_sym == :update,
        api: api
      )
      schema.is_a?(Hash) ? schema[:properties] || schema["properties"] : nil
    end
    private_class_method :overlay_copy_on, :fill_nested_object, :object_type?,
                         :fill_contract_description, :fill_contract_example,
                         :catalog_property_schema,
                         :attributes_properties, :apply_contract_constraints
  end
end
