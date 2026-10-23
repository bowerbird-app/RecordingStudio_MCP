# frozen_string_literal: true

require "digest"

module RecordingStudioMcp
  module McpUi
    UI_SCHEME = "ui://"
    MIME_TYPE = "text/html;profile=mcp-app"
    CONTENT_DIGEST_LENGTH = 12

    module_function

    def adapter
      return @adapter if instance_variable_defined?(:@adapter)

      RecordingStudio::MCP_UI if defined?(RecordingStudio::MCP_UI)
    end

    def adapter=(value)
      @adapter = value
      @content_digests = {}
    end
    private_class_method :adapter=

    def reset_adapter!(to: nil)
      if to.nil?
        remove_instance_variable(:@adapter) if instance_variable_defined?(:@adapter)
      else
        @adapter = to
      end
      @content_digests = {}
    end

    def loaded?
      !adapter.nil?
    end

    def find(widget_id)
      return unless loaded?
      return if widget_id.blank?

      adapter.find(widget_id)
    rescue StandardError => e
      raise unless unknown_widget_error?(e)

      nil
    end

    def list
      return [] unless loaded?

      Array(adapter.list)
    end

    def package(widget_id, data: {})
      return unless loaded?

      adapter.package(widget_id, data: data)
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

    def reset_content_digests!
      @content_digests = {}
    end

    def unknown_widget_error?(error)
      klass = unknown_widget_error_class
      klass && error.instance_of?(klass)
    end

    def unknown_widget_error_class
      return unless adapter.respond_to?(:const_defined?) && adapter.const_defined?(:UnknownWidgetError)

      adapter.const_get(:UnknownWidgetError)
    end

    def content_digest(widget_id)
      content_digests[widget_id] ||= Digest::SHA256.hexdigest(
        package(widget_id, data: {}).to_mcp_resource.fetch(:text)
      )[0, CONTENT_DIGEST_LENGTH]
    end

    def content_digests
      @content_digests ||= {}
    end
    private_class_method :unknown_widget_error?, :unknown_widget_error_class, :content_digest, :content_digests
  end
end
