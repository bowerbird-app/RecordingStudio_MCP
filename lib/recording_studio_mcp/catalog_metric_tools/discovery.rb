# frozen_string_literal: true

module RecordingStudioMcp
  module CatalogMetricTools
    module_function

    def raw_entries(catalog, access_grant)
      if access_grant && defined?(RecordingStudioMetrics::Api::DiscoveryHandler)
        discover(access_grant)
      else
        exposed_definitions(catalog)
      end
    end

    def discover(access_grant)
      result = RecordingStudioMetrics::Api::DiscoveryHandler.call(discovery_context(access_grant))
      Array(result[:metrics] || result["metrics"])
    rescue RecordingStudioApi::AuthorizationError => e
      warn_skipped("(catalog)", e)
      []
    end

    def discovery_context(access_grant)
      RecordingStudioApi::RegisteredEndpointContext.new(
        api_client: access_grant.api_client,
        credential: grant_value(access_grant, :credential),
        access_recording: grant_value(access_grant, :access_recording),
        access_grant: access_grant,
        root_recording: grant_value(access_grant, :root_recording),
        params: {}
      )
    end

    def exposed_definitions(catalog)
      return [] unless defined?(RecordingStudioMetrics) && RecordingStudioMetrics.respond_to?(:definitions)

      RecordingStudioMetrics.definitions.select { |definition| definition.exposed_to_api?(catalog.api) }
                            .map(&:catalog_metadata)
    end
    private_class_method :raw_entries, :discover, :discovery_context, :exposed_definitions
  end
end
