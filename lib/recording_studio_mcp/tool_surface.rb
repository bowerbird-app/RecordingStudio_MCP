# frozen_string_literal: true

module RecordingStudioMcp
  class ToolSurface
    Entry = Data.define(:family, :definition, :metric, :endpoint) do
      def initialize(family:, definition:, metric: nil, endpoint: nil)
        validate_family!(family, metric, endpoint)
        super
      end

      private

      def validate_family!(family, metric, endpoint)
        case family
        when :tree then validate_tree!(metric, endpoint)
        when :metric then validate_metric!(metric, endpoint)
        when :catalog_metric then validate_catalog_metric!(metric, endpoint)
        when :endpoint then validate_endpoint!(metric, endpoint)
        else raise ArgumentError, "Unknown tool family #{family.inspect}"
        end
      end

      def validate_tree!(metric, endpoint)
        return unless metric || endpoint

        raise ArgumentError, "A tree tool has no metric and no endpoint"
      end

      def validate_metric!(metric, endpoint)
        recordable_metric = metric.is_a?(RecordableMetricTools::Tool)
        raise ArgumentError, "A metric tool needs a recordable metric" unless recordable_metric
        raise ArgumentError, "A metric tool has no endpoint" if endpoint
      end

      def validate_catalog_metric!(metric, endpoint)
        catalog_metric = metric.is_a?(CatalogMetricTools::Tool)
        raise ArgumentError, "A catalog metric tool needs a catalog metric" unless catalog_metric
        raise ArgumentError, "A catalog metric tool has no endpoint" if endpoint
      end

      def validate_endpoint!(metric, endpoint)
        raise ArgumentError, "An endpoint tool needs an endpoint" if endpoint.nil?
        raise ArgumentError, "An endpoint tool has no metric" if metric
      end
    end

    def self.for(access_grant: nil, api: nil)
      catalog =
        if api
          Catalog.new(api: api)
        elsif access_grant
          Catalog.for(access_grant)
        else
          Catalog.new(api: Catalog.api_from(nil))
        end
      new(catalog: catalog, access_grant: access_grant)
    end

    TOOL_NAME = /\A[A-Za-z][A-Za-z0-9_.-]*\z/

    def initialize(catalog:, access_grant: nil)
      @catalog = catalog
      @access_grant = access_grant
      @endpoints = advertised_endpoints(catalog)
      @by_name = {}
      insert_tree_tools
      insert_metric_tools
      insert_catalog_metric_tools
      insert_endpoint_tools
      @by_name.freeze
    end

    attr_reader :catalog, :endpoints

    def tree_enabled?
      catalog.type_names.any?
    end

    def endpoints_enabled?
      endpoints.any?
    end

    def known?(name)
      @by_name.key?(name.to_s)
    end

    def tree_tool_names
      Tools.advertised_tree_names(catalog)
    end

    def tree_tool?(name)
      tree_enabled? && tree_tool_names.include?(name.to_s)
    end

    def metric_tool(name)
      entry = @by_name[name.to_s]
      return unless metric_family?(entry)

      entry.metric
    end

    def endpoint_for(name)
      endpoint = @by_name[name.to_s]&.endpoint
      return endpoint if endpoint

      raise ArgumentError, "Unknown endpoint tool #{name}"
    end

    def tool_definitions
      @by_name.values.map(&:definition)
    end

    def tool_names
      @by_name.keys
    end

    def read_only_tool?(name)
      key = name.to_s
      return true if tree_tool?(key) && %w[list show describe].include?(key)
      return true if metric_tool(key)

      @by_name[key]&.endpoint&.http_verb == :get
    end
  end
end

require "recording_studio_mcp/tool_surface/families"
require "recording_studio_mcp/tool_surface/insert"
