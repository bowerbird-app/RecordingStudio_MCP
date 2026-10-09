# frozen_string_literal: true

module RecordingStudioMcp
  module WidgetActions
    module_function

    def call(widget_id:, alias_name:, arguments:, access_grant:, api: nil, version: nil,
             idempotency_key: nil, request_context: nil)
      widget = McpUi.find(widget_id)
      return unknown_alias_result(alias_name) if widget.nil?

      api_key = (api.presence || Catalog.api_from(access_grant)).to_s
      api_version = version.presence || RecordingStudioApi.default_api_version(api: api_key)
      unless McpUi.available?(widget.id, access_grant: access_grant, api: api_key, version: api_version)
        return unauthorized_result
      end

      api_action = resolve_alias(widget, alias_name)
      return unknown_alias_result(alias_name) if api_action.nil?

      tool_name, tool_arguments = tool_for(api_action, arguments, access_grant: access_grant, api: api_key,
                                                                 version: api_version)
      return unknown_alias_result(alias_name) if tool_name.nil?

      wrap(
        Dispatcher.call(
          tool_name: tool_name,
          arguments: tool_arguments,
          access_grant: access_grant,
          idempotency_key: idempotency_key,
          request_context: request_context,
          widget_dispatch: true
        )
      )
    end

    def from_tools_call?(tool_name, meta:, access_grant:)
      return false unless McpUi.loaded?

      resource_uri(meta).present? || unique_widget_for_alias(tool_name, access_grant: access_grant).present?
    end

    def widget_id_for(tool_name, meta:, access_grant:)
      uri = resource_uri(meta)
      return McpUi.widget_id_from_uri(uri) if uri.present?

      unique_widget_for_alias(tool_name, access_grant: access_grant)&.id
    end

    def resolve_alias(widget, alias_name)
      widget.action_for(alias_name)
    rescue StandardError => e
      raise unless e.class.name.end_with?("UnknownActionError")

      nil
    end

    def tool_for(api_action, arguments, access_grant:, api:, version:)
      name = api_action.to_s
      args = stringify_keys(arguments)
      surface = ToolSurface.for(access_grant: access_grant, api: api)
      return [name, args] if surface.known?(name)
      return unless RecordingStudioApi.capability_action(name, version: version, api: api)

      ["capability_action", args.merge("action" => name)]
    end

    def unique_widget_for_alias(alias_name, access_grant:)
      api = Catalog.api_from(access_grant)
      version = RecordingStudioApi.default_api_version(api: api)
      matches = McpUi.list.select do |widget|
        widget.respond_to?(:permits_action?) &&
          widget.permits_action?(alias_name) &&
          McpUi.available?(widget.id, access_grant: access_grant, api: api, version: version)
      end
      matches.one? ? matches.first : nil
    end

    def resource_uri(meta)
      return unless meta.is_a?(Hash)

      ui = meta["ui"] || meta[:ui]
      return unless ui.is_a?(Hash)

      ui["resourceUri"] || ui[:resourceUri]
    end

    def wrap(result)
      if result[:isError]
        message = result.dig(:content, 0, :text).to_s
        {
          content: result[:content],
          structuredContent: { "ok" => false, "data" => nil, "errors" => { "base" => [message] } },
          isError: true
        }
      else
        data = result[:structuredContent]
        {
          content: result[:content],
          structuredContent: { "ok" => true, "data" => data, "errors" => {}, "contextUpdate" => data },
          isError: false
        }
      end
    end

    def unknown_alias_result(alias_name)
      message = "Unknown widget action #{alias_name}"
      {
        content: [{ type: "text", text: message }],
        structuredContent: { "ok" => false, "data" => nil, "errors" => { "alias" => [message] } },
        isError: true
      }
    end

    def unauthorized_result
      message = "Widget is not available for this grant"
      {
        content: [{ type: "text", text: message }],
        structuredContent: { "ok" => false, "data" => nil, "errors" => { "base" => [message] } },
        isError: true
      }
    end

    def stringify_keys(value)
      return {} if value.blank?
      return value.to_unsafe_h.stringify_keys if value.respond_to?(:to_unsafe_h)
      return value.to_h.stringify_keys if value.respond_to?(:to_h)

      {}
    end

    private_class_method :resolve_alias, :tool_for, :unique_widget_for_alias, :resource_uri, :wrap,
                         :unknown_alias_result, :unauthorized_result, :stringify_keys
  end
end
