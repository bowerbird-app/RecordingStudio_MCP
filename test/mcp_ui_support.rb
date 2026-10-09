# frozen_string_literal: true

module McpUiSupport
  module RecordingStudio
    module McpUi
      class UnknownWidgetError < StandardError; end
      class UnknownActionError < StandardError; end

      Widget = Struct.new(:id, :actions, :description, keyword_init: true) do
        def resource_uri
          "ui://#{id.tr('.', '/')}"
        end

        def action_for(alias_name)
          actions.fetch(alias_name.to_s) do
            raise UnknownActionError, "Widget #{id.inspect} has no action #{alias_name.inspect}"
          end
        end

        def permits_action?(alias_name)
          actions.key?(alias_name.to_s)
        end
      end

      Document = Struct.new(:payload) do
        def to_mcp_resource
          payload
        end
      end

      Configuration = Struct.new(:action_executor, :visibility_checker, keyword_init: true)

      class << self
        attr_accessor :widgets, :hidden, :configuration

        def reset!
          self.widgets = {}
          self.hidden = []
          self.configuration = Configuration.new
        end

        def register(id, actions: {}, description: nil)
          widgets[id.to_s] = Widget.new(id: id.to_s, actions: actions.transform_keys(&:to_s), description: description)
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
              text: "<html data-widget=\"#{widget.id}\">#{data}</html>",
              _meta: { ui: { csp: { connectDomains: [], resourceDomains: [] } } }
            }
          )
        end

        def available?(id, **)
          find(id)
          !hidden.include?(id.to_s)
        end
      end
    end

    MCP_UI = McpUi
  end

  module_function

  def install_fake_mcp_ui
    return if defined?(::RecordingStudio::MCP_UI)

    ::RecordingStudio.const_set(:McpUi, RecordingStudio::McpUi)
    ::RecordingStudio.const_set(:MCP_UI, ::RecordingStudio::McpUi)
    ::RecordingStudio::MCP_UI.reset!
  end

  def remove_fake_mcp_ui
    return unless defined?(::RecordingStudio::MCP_UI)
    return unless ::RecordingStudio::MCP_UI.equal?(RecordingStudio::McpUi)

    ::RecordingStudio.send(:remove_const, :MCP_UI)
    ::RecordingStudio.send(:remove_const, :McpUi) if ::RecordingStudio.const_defined?(:McpUi)
  end
end
