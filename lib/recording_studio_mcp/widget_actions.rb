# frozen_string_literal: true

module RecordingStudioMcp
  module WidgetActions
    module_function

    def call(call)
      widget = McpUi.find(call[:widget_id])
      return WidgetResult.failure("Unknown widget action #{call[:alias_name]}", key: "alias") if widget.nil?

      api, version = McpUi.grant_scope(call[:access_grant])
      unless McpUi.available?(widget.id, access_grant: call[:access_grant], api: api, version: version)
        return WidgetResult.failure("Widget is not available for this grant")
      end

      run_alias(widget, call, api, version)
    end

    def from_tools_call?(meta)
      McpUi.loaded? && McpUi.resource_uri(meta).present?
    end

    def widget_id_for(meta)
      McpUi.widget_id_from_uri(McpUi.resource_uri(meta))
    end

    def run_alias(widget, call, api, version)
      api_action = resolve_alias(widget, call[:alias_name])
      return unknown_alias(call[:alias_name]) if api_action.nil?

      tool = tool_for(api_action, call[:arguments], call[:access_grant], api, version)
      return unknown_alias(call[:alias_name]) if tool.nil?

      execute_api(*tool, call)
    end

    def execute_api(tool_name, tool_arguments, call)
      extras = call[:extras] || {}
      WidgetResult.wrap(
        Dispatcher.call(
          tool_name: tool_name,
          arguments: tool_arguments,
          access_grant: call[:access_grant],
          idempotency_key: extras[:idempotency_key],
          request_context: extras[:request_context]
        )
      )
    end

    def unknown_alias(alias_name)
      WidgetResult.failure("Unknown widget action #{alias_name}", key: "alias")
    end

    def resolve_alias(widget, alias_name)
      widget.action_for(alias_name)
    rescue RecordingStudio::MCP_UI::UnknownActionError
      nil
    end

    def tool_for(api_action, arguments, access_grant, api, version)
      name = api_action.to_s
      surface = ToolSurface.for(access_grant: access_grant, api: api)
      return [name, arguments] if surface.known?(name)
      return unless RecordingStudioApi.capability_action(name, version: version, api: api)

      ["capability_action", arguments.merge("action" => name)]
    end

    private_class_method :run_alias, :execute_api, :unknown_alias, :resolve_alias, :tool_for
  end
end
