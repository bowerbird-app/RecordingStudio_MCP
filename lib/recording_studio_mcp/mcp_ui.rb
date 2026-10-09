# frozen_string_literal: true

require "digest"

module RecordingStudioMcp
  # Single place that asks whether RecordingStudio MCP UI is loaded.
  # This gem never requires that engine. Hosts that want widgets add it.
  module McpUi
    UI_SCHEME = "ui://"
    MIME_TYPE = "text/html;profile=mcp-app"
    CONTENT_DIGEST_LENGTH = 12

    module_function

    def loaded?
      defined?(RecordingStudio::MCP_UI)
    end

    def find(widget_id)
      return unless loaded?
      return if widget_id.blank?

      RecordingStudio::MCP_UI.find(widget_id)
    rescue RecordingStudio::MCP_UI::UnknownWidgetError
      nil
    end

    def list
      return [] unless loaded?

      Array(RecordingStudio::MCP_UI.list)
    end

    def package(widget_id, data: {})
      return unless loaded?

      RecordingStudio::MCP_UI.package(widget_id, data: data)
    end

    def widget_id_from_uri(uri)
      return unless loaded?
      return unless uri.is_a?(String)
      return unless uri.start_with?(UI_SCHEME)

      rest = uri.delete_prefix(UI_SCHEME).split(/[?#]/, 2).first
      return if rest.blank?

      rest.tr("/", ".")
    end

    def resource_uri_for(action_name:, api:, version: nil)
      return unless loaded?

      widget = find(RecordingStudioApi.ui_for(action_name, api: api, version: version))
      return unless widget

      resource_uri(widget)
    end

    def resource_uri(widget)
      "#{widget.resource_uri}?v=#{content_digest(widget.id)}"
    end

    def content_digest(widget_id)
      content_digests[widget_id] ||= Digest::SHA256.hexdigest(
        package(widget_id, data: {}).to_mcp_resource.fetch(:text)
      )[0, CONTENT_DIGEST_LENGTH]
    end

    def content_digests
      @content_digests ||= {}
    end
    private_class_method :content_digest, :content_digests
  end
end
