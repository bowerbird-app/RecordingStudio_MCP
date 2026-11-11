# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module_function

    def decorate(payload, output_schema: nil)
      payload[:outputSchema] = output_schema if output_schema
      payload
    end

    def docs_tools(surface)
      Array(surface.tool_entries).map { |entry| docs_tool(entry) }
    end

    def tags_for_entry(entry)
      case entry.family
      when :tree then tree_tags
      when :metric then metric_tags(entry.metric.name)
      when :endpoint then endpoint_tags(entry.endpoint)
      else []
      end
    end

    def openapi_extras(_entry, tool)
      extras = {}
      tags = Array(tool["tags"]).map(&:to_s).reject(&:blank?)
      extras["tags"] = tags if tags.any?
      schema = stringify_schema(tool["outputSchema"])
      extras["outputSchema"] = schema if schema.present?
      extras
    end

    def attach_sidebar!(spec, page)
      tags = openapi_tags(page.tag_groups)
      spec["tags"] = tags if tags.any?
      spec["x-tagGroups"] = page.tag_groups if Array(page.tag_groups).any?
      spec
    end

    def docs_tool(entry)
      payload = entry.definition.dup
      tags = tags_for_entry(entry)
      payload[:tags] = tags if tags.any?
      payload
    end
    private_class_method :docs_tool

    def stringify_schema(value)
      return value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)
      return value.as_json if value.respond_to?(:as_json)

      value
    end
    private_class_method :stringify_schema
  end
end
