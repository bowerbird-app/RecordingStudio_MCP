# frozen_string_literal: true

module RecordingStudioMcp
  module WidgetActions
    module_function

    def call(call)
      widget = McpUi.find(call[:widget_id])
      return WidgetResult.failure("Unknown widget action #{call[:alias_name]}", key: "alias") if widget.nil?

      api_key, api_version = api_scope(call)
      unless McpUi.available?(widget.id, access_grant: call[:access_grant], api: api_key, version: api_version)
        return WidgetResult.failure("Widget is not available for this grant")
      end

      run_alias(widget, call, api_key, api_version)
    end

    def from_tools_call?(tool_name, meta:, access_grant:)
      return false unless McpUi.loaded?

      McpUi.resource_uri(meta).present? || unique_widget_for_alias(tool_name, access_grant).present?
    end

    def widget_id_for(tool_name, meta:, access_grant:)
      uri = McpUi.resource_uri(meta)
      return McpUi.widget_id_from_uri(uri) if uri.present?

      unique_widget_for_alias(tool_name, access_grant)&.id
    end

    def run_alias(widget, call, api_key, api_version)
      api_action = resolve_alias(widget, call[:alias_name])
      return unknown_alias(call[:alias_name]) if api_action.nil?

      tool = tool_for(api_action, call[:arguments], call[:access_grant], api_key, api_version)
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

    def api_scope(call)
      extras = call[:extras] || {}
      api = (call[:api].presence || extras[:api].presence || Catalog.api_from(call[:access_grant])).to_s
      version = call[:version].presence || extras[:version].presence ||
                RecordingStudioApi.default_api_version(api: api)
      [api, version]
    end

    def resolve_alias(widget, alias_name)
      widget.action_for(alias_name)
    rescue StandardError => e
      raise unless e.class.name.end_with?("UnknownActionError")

      nil
    end

    def tool_for(api_action, arguments, access_grant, api, version)
      name = api_action.to_s
      args = stringify_keys(arguments)
      surface = ToolSurface.for(access_grant: access_grant, api: api)
      return [name, args] if surface.known?(name)
      return unless RecordingStudioApi.capability_action(name, version: version, api: api)

      ["capability_action", args.merge("action" => name)]
    end

    def unique_widget_for_alias(alias_name, access_grant)
      api = Catalog.api_from(access_grant)
      version = RecordingStudioApi.default_api_version(api: api)
      matches = McpUi.list.select do |widget|
        widget.respond_to?(:permits_action?) &&
          widget.permits_action?(alias_name) &&
          McpUi.available?(widget.id, access_grant: access_grant, api: api, version: version)
      end
      matches.one? ? matches.first : nil
    end

    def stringify_keys(value)
      return {} if value.blank?
      return value.to_unsafe_h.stringify_keys if value.respond_to?(:to_unsafe_h)
      return value.to_h.stringify_keys if value.respond_to?(:to_h)

      {}
    end

    private_class_method :run_alias, :execute_api, :unknown_alias, :api_scope, :resolve_alias, :tool_for,
                         :unique_widget_for_alias, :stringify_keys
  end
end
