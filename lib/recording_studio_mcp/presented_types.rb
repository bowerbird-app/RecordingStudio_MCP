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
      return type_name(entry, catalog) if KEYS.include?(key.to_s) && entry.is_a?(String)

      apply(entry, catalog)
    end

    def type_name(entry, catalog)
      shown = catalog.displayed_type_name(entry)
      return shown if registered_type_name?(entry, catalog, shown)
      return entry.split("::").last if entry.include?("::")

      shown
    end

    def registered_type_name?(entry, catalog, shown)
      names = catalog.displayed_type_names if catalog.respond_to?(:displayed_type_names)
      return names.key?(entry.to_s) || names.value?(shown) if names

      shown != entry
    end
    private_class_method :rename, :type_name, :registered_type_name?
  end
end
