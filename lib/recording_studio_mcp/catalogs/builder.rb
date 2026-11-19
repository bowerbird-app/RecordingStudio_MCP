# frozen_string_literal: true

require_relative "resolution"

module RecordingStudioMcp
  class Catalogs
    class Builder
      include Resolution

      def initialize(configuration)
        @configuration = configuration
      end

      def call
        by_name = {}
        by_api = {}
        @configuration.servers.each_value { |server| index_server(server, by_name, by_api) }
        [by_api.freeze, by_name.freeze]
      end

      private

      def index_server(server, by_name, by_api)
        built = build_server(server)
        raise RecordingStudioApi::ConfigurationError, duplicate_server(built.name) if by_name.key?(built.name)

        api_key = NamedApi.normalize(built.api)
        raise RecordingStudioApi::ConfigurationError, reused_api(built.name, api_key) if by_api.key?(api_key)

        by_name[built.name] = built
        by_api[api_key] = built
      end

      def build_server(server)
        tools = included_tools(server, server.api)
        types = included_types(server, server.api, tools)
        skills = included_skills(server, server.api, tools, types)
        BuiltServer.new(**server_attrs(server, tools, types, skills))
      end

      def server_attrs(server, tools, types, skills)
        {
          name: server.name,
          api: server.api,
          allow_sensitive: server.allow_sensitive,
          tools: tools.freeze,
          types: types.freeze,
          skills: skills.freeze
        }
      end

      def included_tools(server, api)
        server.included_tools.to_h do |included|
          built = resolve_tool(server, api, included)
          [built.name, built]
        end
      end

      def duplicate_server(name)
        "MCP server #{name} is already registered"
      end

      def reused_api(name, api_key)
        "MCP server #{name} reuses API #{api_key}"
      end
    end
  end
end
