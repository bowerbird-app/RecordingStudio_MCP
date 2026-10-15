# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module Visibility
      OPERATION_ROLES = {
        index: :view,
        show: :view,
        create: :edit,
        update: :edit,
        destroy: :edit
      }.freeze

      def registered_operations
        @registered_operations ||= type_names.flat_map { |type| operations_for(type) }.uniq.freeze
      end

      def visible_operations
        registered_operations.select { |operation| role_allows?(OPERATION_ROLES.fetch(operation)) }
      end

      def capability_actions?
        type_names.any? { |type| visible_capability_names(type).any? }
      end

      def type_names_for(operation)
        name = operation.to_sym
        return [] unless role_allows?(OPERATION_ROLES.fetch(name))

        type_names.select { |type| operations_for(type).include?(name) }
      end

      def destroy_type_names
        type_names_for(:destroy)
      end

      def destroy_type_schema
        type_schema_for(:destroy).merge(
          description: "Type on this named API that allows destroy. Call describe for operations."
        )
      end

      private

      def operations_for(type)
        Array(registration_for(type)&.operations).map(&:to_sym)
      end

      def visible_capability_names(type)
        Array(registration_for(type)&.capability_actions).select { |name| action_visible?(name) }
      end

      def action_visible?(name)
        return true unless grant_reports_role?

        action = RecordingStudioApi.capability_action(name, api: api)
        role_allows?(action&.required_role || :edit)
      end

      def grant_reports_role?
        access_grant.respond_to?(:role)
      end

      def role_allows?(minimum_role)
        return true unless grant_reports_role?

        RecordingStudio::AccessRoles.satisfies?(role: access_grant.role, minimum_role: minimum_role)
      end
    end
  end
end
