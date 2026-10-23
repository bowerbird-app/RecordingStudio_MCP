# frozen_string_literal: true

module McpUiSupport
  module FakeUi
    class UnknownWidgetError < StandardError; end

    Widget = Struct.new(:id, :description, keyword_init: true) do
      def resource_uri
        "ui://#{id.tr('.', '/')}"
      end
    end

    Document = Struct.new(:payload) do
      def to_mcp_resource
        payload
      end
    end

    class << self
      attr_accessor :widgets, :html_extra

      def reset!
        self.widgets = {}
        self.html_extra = nil
      end

      def register(id, description: nil)
        widgets[id.to_s] = Widget.new(id: id.to_s, description: description)
      end

      def find(id)
        widgets.fetch(id.to_s) { raise UnknownWidgetError, "Unknown widget: #{id.inspect}" }
      end

      def list
        widgets.values
      end

      def package(id, data: {})
        widget = find(id)
        Document.new(
          {
            uri: widget.resource_uri,
            name: widget.id,
            mimeType: "text/html;profile=mcp-app",
            text: "<html data-widget=\"#{widget.id}\">#{data}#{html_extra}</html>",
            _meta: { ui: { csp: { connectDomains: [], resourceDomains: [] } } }
          }
        )
      end
    end
  end

  module_function

  def install_fake_mcp_ui
    FakeUi.reset!
    RecordingStudioMcp::McpUi.adapter = FakeUi
    RecordingStudioMcp::McpUi.reset_content_digests!
  end

  def remove_fake_mcp_ui
    RecordingStudioMcp::McpUi.adapter = nil
    RecordingStudioMcp::McpUi.reset_content_digests!
  end
end
