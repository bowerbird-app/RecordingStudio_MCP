# frozen_string_literal: true

module RecordingStudioMcp
  module UiResources
    module_function

    def listed(access_grant)
      return [] unless McpUi.loaded?

      api, version = api_scope(access_grant)
      McpUi.list.filter_map do |widget|
        next unless McpUi.available?(widget.id, access_grant: access_grant, api: api, version: version)

        { uri: widget.resource_uri, name: widget.id, mimeType: McpUi::MIME_TYPE }
      end
    end

    def read(access_grant:, uri:, protocol_version:)
      return Resources::NotFound.new(uri: uri) unless accessible?(access_grant, uri)

      document = McpUi.package(McpUi.widget_id_from_uri(uri), data: {})
      return Resources::NotFound.new(uri: uri) if document.nil?

      Resources::Read.new(payload: Resources.complete({ contents: [document.to_mcp_resource] }, protocol_version))
    end

    def accessible?(access_grant, uri)
      widget_id = McpUi.widget_id_from_uri(uri)
      return false if widget_id.blank?

      api, version = api_scope(access_grant)
      McpUi.available?(widget_id, access_grant: access_grant, api: api, version: version)
    end

    def api_scope(access_grant)
      api = if access_grant.respond_to?(:api_client)
              Catalog.api_from(access_grant)
            else
              "public"
            end
      [api, RecordingStudioApi.default_api_version(api: api)]
    end
    private_class_method :api_scope
  end
end
