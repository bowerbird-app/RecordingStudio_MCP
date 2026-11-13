# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module_function

    def decorate(payload, output_schema: nil)
      payload[:outputSchema] = output_schema if output_schema
      payload
    end

    def docs_page(page, catalog)
      surface = ToolSurface.for(api: catalog.api)
      page.with(overview: Documentation::Overview.markdown(surface))
    end

    def tags_for_entry(entry)
      case entry.family
      when :tree then tree_tags
      when :metric then metric_tags(entry.metric.name)
      when :endpoint then endpoint_tags(entry.endpoint)
      else []
      end
    end

    def openapi_extras(_entry, tool, surface = nil)
      extras = {}
      tags = tags_for_openapi(tool, surface)
      extras["tags"] = tags if tags.any?
      schema = stringify_schema(tool["outputSchema"])
      extras["outputSchema"] = schema if schema.present?
      extras
    end

    def attach_sidebar!(spec, page, group_tags: nil)
      names = tool_sidebar_tags(spec) + type_sidebar_tags(page, group_tags: group_tags)
      tags = openapi_tags(names, descriptions: type_tag_descriptions(page, group_tags: group_tags))
      spec["tags"] = tags if tags.any?
      spec["x-tagGroups"] = page.tag_groups if Array(page.tag_groups).any?
      spec
    end

    def tool_sidebar_tags(spec)
      Array(spec.dig("x-mcp", "tools")).flat_map { |tool| Array(tool["tags"]) }
    end
    private_class_method :tool_sidebar_tags

    def type_sidebar_tags(page, group_tags: nil)
      Array(page.types).flat_map do |entry|
        type_name = (entry["type"] || entry[:type]).to_s
        next [] if type_name.blank?

        type_tags(type_name, api: page.api_key, group_tags: group_tags)
      end
    end
    private_class_method :type_sidebar_tags

    def type_tag_descriptions(page, group_tags: nil)
      Array(page.types).each_with_object({}) do |entry, acc|
        assign_shared_tag_description(acc, entry, page, group_tags)
      end.tap do |acc|
        Array(page.types).each do |entry|
          assign_type_tag_description(acc, entry, page, group_tags)
        end
      end
    end
    private_class_method :type_tag_descriptions

    def assign_shared_tag_description(acc, entry, page, group_tags)
      type_name = (entry["type"] || entry[:type]).to_s
      return if type_name.blank?

      openapi = RecordingStudioApi.recordable_registration_for(type_name, api: page.api_key)&.openapi
      description = openapi.is_a?(Hash) ? openapi.dig(:tag, :description).presence : nil
      return if description.blank?

      type_tags(type_name, api: page.api_key, group_tags: group_tags).each do |tag|
        remember_tag_description(acc, tag, description)
      end
    end
    private_class_method :assign_shared_tag_description

    def assign_type_tag_description(acc, entry, page, group_tags)
      type_name = (entry["type"] || entry[:type]).to_s
      return if type_name.blank?

      description = Documentation::Openapi::Schemas.registered_type_description(type_name, page.api_key)
      return if description.blank?

      type_tags(type_name, api: page.api_key, group_tags: group_tags).each do |tag|
        next if acc.key?(tag)

        remember_tag_description(acc, tag, description)
      end
    end
    private_class_method :assign_type_tag_description

    def remember_tag_description(acc, tag, description)
      if !acc.key?(tag)
        acc[tag] = description
      elsif acc[tag] != description
        acc[tag] = nil
      end
    end
    private_class_method :remember_tag_description

    def tags_for_openapi(tool, surface)
      found = entry_for_tool(tool, surface)
      return tags_for_entry(found) if found

      Array(tool["tags"]).map(&:to_s).reject(&:blank?)
    end
    private_class_method :tags_for_openapi

    def entry_for_tool(tool, surface)
      return unless surface

      name = (tool["name"] || tool[:name]).to_s
      surface.tool_entries.find { |item| item.definition[:name].to_s == name }
    end
    private_class_method :entry_for_tool

    def stringify_schema(value)
      return value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)
      return value.as_json if value.respond_to?(:as_json)

      value
    end
    private_class_method :stringify_schema
  end
end
