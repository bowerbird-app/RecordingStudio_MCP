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
      new(catalog: catalog)
    end

    def initialize(catalog:)
      @catalog = catalog
      @endpoints = Array(catalog.registered_endpoints).sort_by { |endpoint| endpoint.name.to_s }
      @by_name = {}
      insert_tree_tools
      insert_metric_tools
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

    def metric_tools?
      @by_name.each_value.any? { |entry| entry.family == :metric }
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
      return unless entry&.family == :metric

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

    private

    def insert_tree_tools
      return unless tree_enabled?

      Tools.tree_definitions(catalog).each do |definition|
        insert(definition.fetch(:name), Entry.new(family: :tree, definition: definition))
      end
    end

    def insert_metric_tools
      RecordableMetricTools.collect(catalog).each do |metric|
        insert(metric.name.to_s, metric_entry(metric))
      end
    end

    def insert_endpoint_tools
      reserved = @endpoints.map { |endpoint| endpoint.name.to_s }.select { |name| Tools::TREE_NAMES.include?(name) }
      if reserved.any?
        raise RecordingStudioApi::ConfigurationError,
              "Registered endpoint names collide with tree tools: #{reserved.sort.join(', ')}"
      end

      @endpoints.each do |endpoint|
        insert(endpoint.name.to_s, endpoint_entry(endpoint))
      end
    end

    def metric_entry(metric)
      Entry.new(
        family: :metric,
        definition: Tools.metric_tool(metric),
        metric: metric
      )
    end

    def endpoint_entry(endpoint)
      Entry.new(
        family: :endpoint,
        definition: Tools.endpoint_tool(endpoint, api: catalog.api),
        endpoint: endpoint
      )
    end

    def insert(name, entry)
      key = name.to_s
      if entry.family != :tree && Tools::TREE_NAMES.include?(key)
        raise RecordingStudioApi::ConfigurationError, reserved_name_message(key, entry)
      end
      raise RecordingStudioApi::ConfigurationError, duplicate_name_message(key, entry) if @by_name.key?(key)

      @by_name[key] = entry
    end

    def reserved_name_message(name, entry)
      return "Registered endpoint names collide with tree tools: #{name}" if entry.family == :endpoint

      "Recordable metric tool #{name} collides with a tree tool"
    end

    def duplicate_name_message(name, entry)
      if entry.family == :endpoint
        "Registered endpoint name #{name} collides with an existing tool"
      else
        "Recordable metric tool #{name} collides with an existing tool"
      end
    end
  end
end
