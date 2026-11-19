# frozen_string_literal: true

module RecordingStudioMcp
  class Catalogs
    GENERIC_NAMES = GenericTools.names.freeze
    DESCRIBE_NAME = "describe"

    def initialize(configuration)
      @configuration = configuration
      @by_api = nil
      @by_name = nil
    end

    def server_for(api:)
      build_if_needed
      @by_api[NamedApi.normalize(api)]
    end

    def server_named(name)
      build_if_needed
      @by_name[name.to_s]
    end

    def servers
      build_if_needed
      @by_name.values
    end

    def invalidate!
      @by_api = nil
      @by_name = nil
    end

    def build!
      @by_api, @by_name = Builder.new(@configuration).call
      self
    end

    def audit_lines
      servers.flat_map { |server| Audit.lines(server) }
    end

    def audit!
      mismatches = servers.flat_map { |server| Audit.mismatches(server) }
      raise RecordingStudioApi::ConfigurationError, mismatches.join("\n") if mismatches.any?

      audit_lines
    end

    private

    def build_if_needed
      build! if @by_name.nil?
    end

    class Builder
      def initialize(configuration)
        @configuration = configuration
      end

      def call
        by_name = {}
        by_api = {}
        @configuration.servers.each_value do |server|
          built = build_server(server)
          if by_name.key?(built.name)
            raise RecordingStudioApi::ConfigurationError,
                  "MCP server #{built.name} is already registered"
          end

          api_key = NamedApi.normalize(built.api)
          if by_api.key?(api_key)
            raise RecordingStudioApi::ConfigurationError,
                  "MCP server #{built.name} reuses API #{api_key}"
          end

          by_name[built.name] = built
          by_api[api_key] = built
        end
        [by_api.freeze, by_name.freeze]
      end

      private

      def build_server(server)
        api = server.api
        tools, filters = included_tools(server, api)
        types = included_types(server, api, tools)
        skills = included_skills(server, api, tools, types)
        BuiltServer.new(
          name: server.name,
          api: api,
          allow_sensitive: server.allow_sensitive,
          tools: tools.freeze,
          types: types.freeze,
          skills: skills.freeze,
          filters: filters.freeze
        )
      end

      def included_tools(server, api)
        tools = {}
        filters = {}
        server.included_tools.each do |included|
          built = resolve_tool(server, api, included)
          tools[built.name] = built
          filters[built.name] = included.filters if included.filters.any?
        end
        [tools, filters]
      end

      def resolve_tool(server, api, included)
        name = included.name
        registration = @configuration.tool(name)
        return built_registered_tool(server, api, included, registration) if registration
        return built_metric_tool(server, api, included, name) if metric_tool?(api, name)

        raise RecordingStudioApi::ConfigurationError, "MCP server #{server.name} includes unknown tool #{name}"
      end

      def built_registered_tool(server, api, included, registration)
        lookup = lookup_for(api, registration)
        sensitive = lookup&.sensitive == true
        assert_sensitive!(server, included, registration.name, sensitive)
        BuiltTool.new(
          name: registration.name,
          registration: registration,
          title: included.title.presence || registration.title,
          description: included.description.presence || registration.description,
          allow_sensitive: included.allow_sensitive,
          sensitive: sensitive,
          lookup: lookup,
          metric: nil,
          family: family_for(registration)
        )
      end

      def built_metric_tool(server, api, included, name)
        metric = metric_by_name(api, name)
        sensitive = false
        assert_sensitive!(server, included, name, sensitive)
        BuiltTool.new(
          name: name,
          registration: nil,
          title: included.title.presence || metric.definition_options[:title],
          description: included.description.presence || metric.definition_options[:description],
          allow_sensitive: included.allow_sensitive,
          sensitive: sensitive,
          lookup: nil,
          metric: metric,
          family: :metric
        )
      end

      def family_for(registration)
        return :endpoint if registration.target.endpoint?
        return :tree if GENERIC_NAMES.include?(registration.name)

        :tree
      end

      def lookup_for(api, registration)
        return if registration.name == "capability_action" && registration.generic?

        kwargs = { api: api }
        kwargs[:recordable_type] = registration.type if registration.type.present?
        case registration.target.kind
        when :operation
          return if registration.generic?

          kwargs[:operation] = registration.target.value
        when :action
          return if registration.generic?

          kwargs[:action] = registration.target.value
        when :endpoint
          kwargs[:endpoint] = registration.target.value
        end
        result = RecordingStudioApi.lookup(**kwargs)
        raise RecordingStudioApi::ConfigurationError, unknown_api_target(registration, api) if result.nil?

        assert_fields!(registration, result)
        result
      end

      def unknown_api_target(registration, api)
        "MCP tool #{registration.name} names API #{registration.target.kind} #{registration.target.value} " \
          "that is not on #{api}"
      end

      def assert_fields!(registration, lookup)
        contract = stringify_contract(lookup.input_contract)
        registration.input.each_key do |field|
          next if protocol_field?(registration, field)
          next if contract.key?(field.to_s)

          raise RecordingStudioApi::ConfigurationError,
                "MCP tool #{registration.name} field #{field} is not on the API contract"
        end
      end

      def protocol_field?(registration, _field)
        registration.generic?
      end

      def stringify_contract(contract)
        return {} if contract.blank?

        contract.to_h.transform_keys(&:to_s)
      end

      def assert_sensitive!(server, included, name, sensitive)
        return unless sensitive
        return if server.allow_sensitive || included.allow_sensitive == true

        raise RecordingStudioApi::ConfigurationError,
              "MCP server #{server.name} includes sensitive tool #{name} without allow_sensitive"
      end

      def included_types(server, api, tools)
        names = type_names_for(server, tools)
        names.to_h do |type_name|
          definition = @configuration.type(type_name)
          if definition.nil?
            raise RecordingStudioApi::ConfigurationError,
                  "MCP server #{server.name} uses unregistered type #{type_name}"
          end

          registration = RecordingStudioApi.recordable_registration_for(type_name, api: api)
          if registration.nil?
            raise RecordingStudioApi::ConfigurationError,
                  "MCP type #{type_name} is not on API #{api}"
          end

          [type_name, definition]
        end
      end

      def type_names_for(server, tools)
        names = @configuration.types.keys.select do |type_name|
          RecordingStudioApi.recordable_registration_for(type_name, api: server.api)
        end
        names |= tools.each_value.filter_map { |tool| tool.registration&.type&.to_s }
        names |= server.included_skills.filter_map { |name| @configuration.skill(name)&.type&.to_s }
        names.compact.uniq.sort
      end

      def included_skills(server, api, tools, types)
        server.included_skills.to_h do |name|
          skill = @configuration.skill(name)
          if skill.nil?
            raise RecordingStudioApi::ConfigurationError,
                  "MCP server #{server.name} includes unknown skill #{name}"
          end

          assert_skill!(skill, api, tools, types)
          [name, skill]
        end
      end

      def assert_skill!(skill, api, tools, types)
        if skill.type.present? && !(types.key?(skill.type.to_s) || RecordingStudioApi.recordable_registration_for(
          skill.type, api: api
        ))
          raise RecordingStudioApi::ConfigurationError,
                "MCP skill #{skill.name} type #{skill.type} is not on API #{api}"
        end

        skill.tools.each do |tool_name|
          next if tool_name.to_s == DESCRIBE_NAME
          next if tools.key?(tool_name.to_s)

          raise RecordingStudioApi::ConfigurationError, "MCP skill #{skill.name} names unknown tool #{tool_name}"
        end
      end

      def metric_tool?(api, name)
        metric_by_name(api, name).present?
      end

      def metric_by_name(api, name)
        catalog = Catalog.new(api: api, server: false)
        with_unfiltered_catalog_metrics do
          (MetricTools.collect_recordable(catalog) + MetricTools.collect_catalog(catalog, nil)).find do |metric|
            metric.name.to_s == name
          end
        end
      end

      def with_unfiltered_catalog_metrics
        previous = RecordingStudioMcp.configuration.catalog_metric_resources
        RecordingStudioMcp.configuration.catalog_metric_resources = nil
        yield
      ensure
        RecordingStudioMcp.configuration.catalog_metric_resources = previous
      end
    end

    module Audit
      module_function

      def lines(server)
        ["server #{server.name} api=#{server.api} allow_sensitive=#{server.allow_sensitive}"] +
          tool_lines(server) +
          ["types #{server.type_names.join(', ').presence || '(none)'}",
           "skills #{server.skill_names.join(', ').presence || '(none)'}"]
      end

      def tool_lines(server)
        (["describe"] + server.tools.keys).uniq.map do |name|
          tool = server.tool(name)
          sensitive = name == "describe" ? false : tool.sensitive
          "  tool #{name} sensitive=#{sensitive}"
        end
      end

      def mismatches(server)
        server.tools.each_value.filter_map do |tool|
          next unless tool.sensitive
          next if server.allow_sensitive || tool.allow_sensitive == true

          "server #{server.name} tool #{tool.name} is sensitive without allow_sensitive"
        end
      end
    end
  end
end
