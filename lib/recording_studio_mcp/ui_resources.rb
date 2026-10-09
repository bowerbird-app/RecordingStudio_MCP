# frozen_string_literal: true

module RecordingStudioMcp
  module UiResources
    module_function

    def listed(access_grant)
      return [] unless McpUi.loaded?

      McpUi.list.filter_map do |widget|
        next unless visible?(widget.id, access_grant)

        { uri: widget.resource_uri, name: widget.id, mimeType: McpUi::MIME_TYPE }
      end
    end

    def read(access_grant:, uri:, protocol_version:)
      return Resources::NotFound.new(uri: uri) unless accessible?(access_grant, uri)

      document = McpUi.package(McpUi.widget_id_from_uri(uri), data: {})
      return Resources::NotFound.new(uri: uri) if document.nil?

      Resources::Read.new(
        payload: ResultShape.complete({ contents: [document.to_mcp_resource] }, protocol_version: protocol_version)
      )
    end

    def accessible?(access_grant, uri)
      widget_id = McpUi.widget_id_from_uri(uri)
      return false if widget_id.blank?

      visible?(widget_id, access_grant)
    end

    def visible?(widget_id, access_grant)
      return false if McpUi.find(widget_id).nil?

      api = Catalog.api_from(access_grant)
      version = RecordingStudioApi.default_api_version(api: api)
      RecordingStudioApi.actions_for_ui(widget_id, api: api, version: version).any?
    end
    private_class_method :visible?
  end
end
