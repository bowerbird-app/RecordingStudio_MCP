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
      tree_tool?(name) || @endpoint_by_name.key?(name.to_s)
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
      definitions
    end

    def tool_names
      names = []
      names.concat(Tools::TREE_NAMES) if tree_enabled?
      names.concat(endpoints.map { |endpoint| endpoint.name.to_s })
      names
    end

    def read_only_tool?(name)
      key = name.to_s
      return true if tree_tool?(key) && %w[list show describe].include?(key)

      @endpoint_by_name[key]&.http_verb == :get
    end

    private

    def reject_collisions!
      collisions = @endpoint_by_name.keys & Tools::TREE_NAMES
      return if collisions.empty?

      raise RecordingStudioApi::ConfigurationError,
            "Registered endpoint names collide with tree tools: #{collisions.sort.join(', ')}"
    end
  end
end
