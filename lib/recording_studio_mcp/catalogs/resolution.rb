# frozen_string_literal: true

require_relative "lookups"
require_relative "types"
require_relative "audit"

module RecordingStudioMcp
  class Catalogs
    module Resolution
      include Lookups
      include Types

      def resolve_tool(server, api, included)
        name = included.name
        registration = @configuration.tool(name)
        return built_registered_tool(server, api, included, registration) if registration
        return built_metric_tool(server, api, included, name) if metric_tool?(api, name)

        raise RecordingStudioApi::ConfigurationError, "MCP server #{server.name} includes unknown tool #{name}"
      end

      def built_registered_tool(server, api, included, registration)
        lookup, sensitive = resolve_lookup(api, registration)
        assert_sensitive!(server, included, registration.name, sensitive)
        family = registration.target.endpoint? ? :endpoint : :tree
        built_tool(included, name: registration.name, registration: registration, family: family,
                             lookup: lookup, sensitive: sensitive)
      end

      def built_metric_tool(server, api, included, name)
        metric = metric_by_name(api, name)
        assert_sensitive!(server, included, name, false)
        built_tool(included, name: name, family: :metric, metric: metric,
                             title: metric.definition_options[:title],
                             description: metric.definition_options[:description])
      end

      def built_tool(included, **attrs)
        registration = attrs[:registration]
        BuiltTool.new(**built_tool_attrs(included, registration, attrs))
      end

      def built_tool_attrs(included, registration, attrs)
        {
          name: attrs[:name], registration: registration, family: attrs[:family],
          title: included.title.presence || attrs[:title] || registration&.title,
          description: included.description.presence || attrs[:description] || registration&.description,
          allow_sensitive: included.allow_sensitive, sensitive: attrs[:sensitive] == true,
          lookup: attrs[:lookup], metric: attrs[:metric]
        }
      end

      def assert_sensitive!(server, included, name, sensitive)
        Audit.assert_sensitive!(server, included, name, sensitive)
      end

      def included_skills(server, api, tools, types)
        server.included_skills.to_h do |name|
          skill = @configuration.skill(name)
          if skill.nil?
            raise RecordingStudioApi::ConfigurationError, "MCP server #{server.name} includes unknown skill #{name}"
          end

          assert_skill!(skill, api, tools, types)
          [name, skill]
        end
      end

      def assert_skill!(skill, api, tools, types)
        assert_skill_type!(skill, api, types)
        skill.tools.each { |tool_name| assert_skill_tool!(skill, tools, tool_name) }
      end

      def assert_skill_type!(skill, api, types)
        return if skill.type.blank? || types[skill.type.to_s]
        return if RecordingStudioApi.recordable_registration_for(skill.type, api: api)

        raise RecordingStudioApi::ConfigurationError,
              "MCP skill #{skill.name} type #{skill.type} is not on API #{api}"
      end

      def assert_skill_tool!(skill, tools, tool_name)
        return if tool_name.to_s == DESCRIBE_NAME || tools.key?(tool_name.to_s)

        raise RecordingStudioApi::ConfigurationError, "MCP skill #{skill.name} names unknown tool #{tool_name}"
      end
    end
  end
end
