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
    rescue RecordingStudio::MCP_UI::UnknownWidgetError
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

      find(RecordingStudioApi.ui_for(action_name, api: api, version: version))&.resource_uri
    end

    def resource_uri(meta)
      return unless meta.is_a?(Hash)

      ui = meta["ui"] || meta[:ui]
      return unless ui.is_a?(Hash)

      ui["resourceUri"] || ui[:resourceUri]
    end

    def grant_scope(access_grant)
      api = Catalog.api_from(access_grant)
      [api, RecordingStudioApi.default_api_version(api: api)]
    end

    def operation_visible?(widget:, access_grant:, api:, version:)
      return false if access_grant.nil?
      return false unless Catalog.api_from(access_grant).to_s == api.to_s

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
    private_class_method :default_action_executor
  end
end
