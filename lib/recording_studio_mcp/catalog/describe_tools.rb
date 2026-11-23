# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module DescribeTools
      private

      def type_paragraph(recordable_type)
        registered = resolved_server&.types&.[](recordable_type.to_s)
        return registered.description if registered&.description.present?

        Documentation::Openapi::Schemas.registered_type_description(recordable_type, api)
      end

      def describe_tools(recordable_type, registration)
        (generic_tools_for(recordable_type, registration) + typed_tools_for(recordable_type)).uniq
      end

      def generic_tools_for(recordable_type, registration)
        return [] unless resolved_server

        operations = Array(registration&.operations).map(&:to_sym)
        Catalogs::GENERIC_NAMES.select { |name| generic_tool_for?(name, recordable_type, operations) }
      end

      def generic_tool_for?(name, recordable_type, operations)
        return false unless resolved_server.tool?(name)
        return true if name == "capability_action" && visible_capability_names(recordable_type).any?

        operation = Tools::TREE_OPERATION_TOOLS.key(name)
        operation && operations.include?(operation)
      end

      def typed_tools_for(recordable_type)
        return [] unless resolved_server

        resolved_server.tools.each_value.filter_map do |tool|
          next if Catalogs::GENERIC_NAMES.include?(tool.name)
          next unless listed_for_type?(tool.registration, recordable_type)

          tool.name
        end
      end

      def listed_for_type?(registration, recordable_type)
        return false if registration.nil?
        return registration.type.to_s == recordable_type.to_s if registration.type.present?
        return false unless registration.target.action?

        visible_capability_names(recordable_type).include?(registration.target.value.to_s)
      end

      def describe_skills(recordable_type)
        return [] unless resolved_server

        resolved_server.skills.each_value.filter_map do |skill|
          skill.name if skill.type.blank? || skill.type.to_s == recordable_type.to_s
        end
      end

      def advertised_capability_actions(recordable_type, title: :docs)
        return unless capability_actions_advertised?

        enabled_capability_actions(recordable_type, title: title)
      end
    end
  end
end
