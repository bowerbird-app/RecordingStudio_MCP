# frozen_string_literal: true

module RecordingStudioMcp
  module CatalogMetricTools
    module_function

    def raw_entries(catalog, access_grant)
      if access_grant && defined?(RecordingStudioMetrics::Api::DiscoveryHandler)
        discover(catalog, access_grant)
      else
        exposed_definitions(catalog)
      end
    end

    def discover(catalog, access_grant)
      resources_for(catalog).flat_map { |resource| discover_resource(access_grant, resource) }
    end

    def discover_resource(access_grant, resource)
      result = RecordingStudioMetrics::Api::DiscoveryHandler.call(discovery_context(access_grant, resource))
      Array(result[:metrics] || result["metrics"])
    rescue StandardError
      warn_skipped(resource)
      []
    end

    def resources_for(catalog)
      names = exposed_definitions(catalog).filter_map { |entry| read_key(entry, :resource)&.to_s.presence }
      names.uniq.select { |resource| resource_allowed?(resource) }
    end

    def discovery_context(access_grant, resource)
      RecordingStudioApi::RegisteredEndpointContext.new(
        api_client: access_grant.api_client,
        credential: grant_value(access_grant, :credential),
        access_recording: grant_value(access_grant, :access_recording),
        access_grant: access_grant,
        root_recording: grant_value(access_grant, :root_recording),
        params: { filters: { resource: resource } }
      )
    end

    def exposed_definitions(catalog)
      return [] unless defined?(RecordingStudioMetrics) && RecordingStudioMetrics.respond_to?(:definitions)

      RecordingStudioMetrics.definitions.select { |definition| definition.exposed_to_api?(catalog.api) }
                            .map(&:catalog_metadata)
    end
    private_class_method :raw_entries, :discover, :discover_resource, :resources_for, :discovery_context,
                         :exposed_definitions
  end
end
