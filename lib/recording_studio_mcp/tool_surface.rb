# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    def self.for(access_grant: nil, api: nil)
      catalog =
        if api
          Catalog.new(api: api)
        elsif access_grant
          Catalog.for(access_grant)
        else
          Catalog.new(api: Catalog.api_from(nil))
        end
      new(catalog: catalog)
    end

    def initialize(catalog:)
      @catalog = catalog
      @endpoints = Array(catalog.registered_endpoints).sort_by { |endpoint| endpoint.name.to_s }
      @endpoint_by_name = @endpoints.index_by { |endpoint| endpoint.name.to_s }
      @host_tools = Array(RecordingStudioMcp.configuration.host_tools)
      @host_tool_by_name = @host_tools.index_by(&:name)
      reject_collisions!
    end

    attr_reader :catalog, :endpoints

    def tree_enabled?
      catalog.type_names.any?
    end

    def endpoints_enabled?
      endpoints.any?
    end

    def known?(name)
      tree_tool?(name) || @endpoint_by_name.key?(name.to_s) || host_tool?(name)
    end

    def host_tool?(name)
      @host_tool_by_name.key?(name.to_s)
    end

    def host_tool_for(name)
      @host_tool_by_name.fetch(name.to_s) do
        raise ArgumentError, "Unknown host tool #{name}"
      end
    end

    def tree_tool?(name)
      tree_enabled? && Tools::TREE_NAMES.include?(name.to_s)
    end

    def endpoint_for(name)
      @endpoint_by_name.fetch(name.to_s) do
        raise ArgumentError, "Unknown endpoint tool #{name}"
      end
    end

    def tool_definitions
      definitions = []
      definitions.concat(Tools.tree_definitions(catalog)) if tree_enabled?
      definitions.concat(endpoints.map { |endpoint| Tools.endpoint_tool(endpoint) })
      definitions.concat(@host_tools.map(&:definition))
      definitions
    end

    def tool_names
      names = []
      names.concat(Tools::TREE_NAMES) if tree_enabled?
      names.concat(endpoints.map { |endpoint| endpoint.name.to_s })
      names.concat(@host_tools.map(&:name))
      names
    end

    def read_only_tool?(name)
      key = name.to_s
      return true if tree_tool?(key) && %w[list show describe].include?(key)
      return @host_tool_by_name[key].read_only if host_tool?(key)

      @endpoint_by_name[key]&.http_verb == :get
    end

    private

    def reject_collisions!
      endpoint_collisions = @endpoint_by_name.keys & Tools::TREE_NAMES
      if endpoint_collisions.any?
        raise RecordingStudioApi::ConfigurationError,
              "Registered endpoint names collide with tree tools: #{endpoint_collisions.sort.join(', ')}"
      end

      host_collisions = @host_tool_by_name.keys & (Tools::TREE_NAMES | @endpoint_by_name.keys)
      return if host_collisions.empty?

      raise RecordingStudioApi::ConfigurationError,
            "Host tool names collide with tree or endpoint tools: #{host_collisions.sort.join(', ')}"
    end
  end
end
