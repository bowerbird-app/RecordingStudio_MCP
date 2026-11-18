# frozen_string_literal: true

module RecordingStudioMcp
  module PresentedTypes
    KEYS = %w[type recordable_type].freeze

    module_function

    def apply(value, catalog)
      case value
      when Array
        value.map { |entry| apply(entry, catalog) }
      when Hash
        value.each_with_object({}) do |(key, entry), copy|
          copy[key] = rename(key, entry, catalog)
        end
      else
        value
      end
    end

    def rename(key, entry, catalog)
      return catalog.displayed_type_name(entry) if KEYS.include?(key.to_s) && entry.is_a?(String)

      apply(entry, catalog)
    end
    private_class_method :rename
  end
end
