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
        grouped = registered_types.group_by { |type| candidate_public_name(type) }
        grouped.each_with_object({}) do |(name, types), map|
          if types.one?
            map[types.first] = name
          else
            warn_public_name_clash(name, types)
            types.each { |type| map[type] = type }
          end
        end
      end

      def candidate_public_name(type)
        named = registration_public_name(registration_for(type))
        return named if named

        type.to_s.demodulize
      end

      def registration_public_name(registration)
        return unless registration.respond_to?(:public_name)

        value = registration.public_name
        return if value.blank?

        value.to_s
      end

      def type_name_matches(name)
        registered_types.select { |type| candidate_public_name(type) == name }.uniq
      end

      def warn_public_name_clash(name, types)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        listed = types.map(&:to_s).sort.join(", ")
        Rails.logger.warn(
          "[RecordingStudioMcp] #{listed} share public name #{name} on API #{api}. " \
          "Showing the full class names. The gem should set public_name."
        )
      end
    end
  end
end
