# frozen_string_literal: true

module RecordingStudioMcp
  module NestedSchema
    LIFTED_KEYS = %w[type enum description required name].freeze

    module_function

    def copy(property)
      stringify(property)
    end

    def copy_nested(field, *keys)
      keys.each_with_object({}) do |key, copied|
        value = field.respond_to?(:[]) ? field[key] || field[key.to_s] : nil
        next if value.nil?

        fragment = copy(value)
        copied[key] = fragment.respond_to?(:deep_symbolize_keys) ? fragment.deep_symbolize_keys : fragment
      end
    end

    def object_fragment(field)
      copied = copy_nested(field, :items, :properties, :additionalProperties)
      required = field.respond_to?(:[]) ? field[:required] || field["required"] : nil
      copied[:required] = required.map(&:to_s) if required.is_a?(Array)
      copied
    end

    def stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), copy|
          copy[key.to_s] = stringify(entry)
        end
      when Array
        value.map { |entry| stringify(entry) }
      else
        value
      end
    end
    private_class_method :stringify
  end
end
