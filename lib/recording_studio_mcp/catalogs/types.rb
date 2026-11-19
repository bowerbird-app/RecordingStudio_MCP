# frozen_string_literal: true

module RecordingStudioMcp
  class Catalogs
    module Types
      def included_types(server, api, tools)
        type_names_for(server, tools).to_h { |type_name| [type_name, registered_type!(server, api, type_name)] }
      end

      def registered_type!(server, api, type_name)
        definition = @configuration.type(type_name)
        raise RecordingStudioApi::ConfigurationError, unregistered_type(server, type_name) if definition.nil?
        raise RecordingStudioApi::ConfigurationError, missing_api_type(api, type_name) if api_type_missing?(
          api, type_name
        )

        definition
      end

      def type_names_for(server, tools)
        names = tools.each_value.flat_map { |tool| types_used_by_tool(server.api, tool) }
        names += server.included_skills.filter_map { |name| @configuration.skill(name)&.type&.to_s }
        names.compact.uniq.sort
      end

      def types_used_by_tool(api, tool)
        registration = tool.registration
        return [] unless registration
        return [registration.type] if registration.type.present?

        registered_operation_types(api, registration)
      end

      def registered_operation_types(api, registration)
        return [] unless generic_operation?(registration)

        operation = OPERATION_TOOLS.fetch(registration.name)
        @configuration.types.keys.select do |type_name|
          RecordingStudioApi.recordable_registration_for(type_name, api: api)&.supports_operation?(operation)
        end
      end

      def unregistered_type(server, type_name)
        "MCP server #{server.name} uses unregistered type #{type_name}"
      end

      def missing_api_type(api, type_name)
        "MCP type #{type_name} is not on API #{api}"
      end

      def api_type_missing?(api, type_name)
        RecordingStudioApi.recordable_registration_for(type_name, api: api).nil?
      end
    end
  end
end
