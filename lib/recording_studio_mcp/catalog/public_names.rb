# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module PublicNames
      def displayed_type_name(type)
        displayed_type_names.fetch(type.to_s, type.to_s)
      end

      def displayed_type_names
        @displayed_type_names ||= build_displayed_type_names.freeze
      end

      private

      def build_displayed_type_names
        registered_types.index_with { |type| registration_for(type).public_name }
      end

      def type_name_matches(name)
        registered_types.select { |type| registration_for(type).public_name == name }
      end
    end
  end
end
