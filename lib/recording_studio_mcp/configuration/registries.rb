# frozen_string_literal: true

module RecordingStudioMcp
  class Configuration
    module Registries
      def catalogs
        @catalogs ||= Catalogs.new(self)
      end

      def tool(name)
        @tools[name.to_s]
      end

      def type(name)
        @types[name.to_s]
      end

      def skill(name)
        @mcp_skills[name.to_s]
      end

      def add_tool(registration, override: false)
        key = registration.name.to_s
        existing = @tools[key]
        assert_override!(existing, registration) if existing && !override
        store_entry(@tools, key, registration)
      end

      def add_type(registration)
        store_entry(@types, registration.type.to_s, registration)
      end

      def add_skill(registration)
        store_entry(@mcp_skills, registration.name.to_s, registration)
      end

      def add_server(registration)
        store_entry(@servers, registration.name.to_s, registration)
      end

      def update_skill_catalog
        @skill_catalog = yield(@skill_catalog)
      end

      def update_event_catalog
        @event_catalog = yield(@event_catalog)
      end

      private

      def store_entry(collection, key, registration)
        collection[key] = registration
        catalogs.invalidate!
        registration
      end

      def assert_override!(existing, incoming)
        return if existing.type.to_s == incoming.type.to_s && existing.target == incoming.target

        raise RecordingStudioApi::ConfigurationError,
              "MCP tool #{incoming.name} override cannot change type or target"
      end
    end
  end
end
