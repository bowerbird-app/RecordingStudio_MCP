# frozen_string_literal: true

module RecordingStudioMcp
  # Single place that asks whether RecordingStudio MCP UI is loaded.
  # This gem never requires that engine. Hosts that want widgets add it.
  module McpUi
    UI_SCHEME = "ui://"
    MIME_TYPE = "text/html;profile=mcp-app"

    module_function

    def loaded?
      defined?(RecordingStudio::MCP_UI)
    end

    def find(widget_id)
      return unless loaded?
      return if widget_id.blank?

      RecordingStudio::MCP_UI.find(widget_id)
    rescue StandardError => e
      raise unless unknown_widget_error?(e)

      nil
    end

    def list
      return [] unless loaded?

      Array(RecordingStudio::MCP_UI.list)
    end

    def available?(widget_id, access_grant:, api:, version:)
      return false unless loaded?
      return false if find(widget_id).nil?

      RecordingStudio::MCP_UI.available?(
        widget_id,
        access_grant: access_grant,
        api: api,
        version: version
      ) == true
    end

    def package(widget_id, data: {})
      return unless loaded?

      RecordingStudio::MCP_UI.package(widget_id, data: data)
    end

    def widget_id_from_uri(uri)
      return unless loaded?
      return unless uri.is_a?(String)
      return unless uri.start_with?(UI_SCHEME)

      rest = uri.delete_prefix(UI_SCHEME)
      return if rest.blank? || rest.include?("?") || rest.include?("#")

      rest.tr("/", ".")
    end

    def resource_uri_for(action_name:, api:, version: nil)
      return unless loaded?
      return unless RecordingStudioApi.respond_to?(:ui_for)

      widget_id = RecordingStudioApi.ui_for(action_name, api: api, version: version)
      find(widget_id)&.resource_uri
    end

    def operation_visible?(widget:, access_grant:, api:, version:)
      return false if access_grant.nil?
      return false unless RecordingStudioApi.respond_to?(:actions_for_ui)

      grant_api = Catalog.api_from(access_grant).to_s
      return false unless grant_api == api.to_s

      RecordingStudioApi.actions_for_ui(widget.id, api: api, version: version).any?
    end

    def install_host_hooks
      return unless loaded?

      config = RecordingStudio::MCP_UI.configuration
      config.visibility_checker ||= method(:operation_visible?)
      config.action_executor ||= default_action_executor
    end

    def default_action_executor
      lambda do |request|
        RecordingStudioMcp.dispatch_widget_action(
          widget_id: request.widget.id,
          alias_name: request.alias_name,
          arguments: request.arguments,
          access_grant: request.access_grant
        )
      end
    end

    def resource_uri(meta)
      return unless meta.is_a?(Hash)

      ui = meta["ui"] || meta[:ui]
      return unless ui.is_a?(Hash)

      ui["resourceUri"] || ui[:resourceUri]
    end

    def unknown_widget_error?(error)
      error.class.name.end_with?("UnknownWidgetError")
    end
    private_class_method :unknown_widget_error?, :default_action_executor
  end
end
