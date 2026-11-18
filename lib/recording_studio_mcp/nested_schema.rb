# frozen_string_literal: true

module RecordingStudioMcp
  module NestedSchema
    LIFTED_KEYS = %w[type enum description required name].freeze

    module_function

    def copy(property)
      stringify(property)
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
