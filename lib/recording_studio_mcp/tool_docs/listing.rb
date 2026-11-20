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

    def tags_for_entry(entry, api: nil)
      case entry.family
      when :tree then tree_entry_tags(entry, api)
      when :metric then metric_tags(entry.metric.name)
      when :endpoint then endpoint_tags(entry.endpoint, api: api)
      else []
      end
    end

    def tree_entry_tags(entry, api)
      name = (entry.definition[:name] || entry.definition["name"]).to_s
      return tree_tags if Tools::TREE_NAMES.include?(name) || api.nil?

      named_tree_tags(name, api)
    end
    private_class_method :tree_entry_tags

    def named_tree_tags(name, api)
      registration = named_tree_registration(name, api)
      type_name = registration&.type.to_s
      return tree_tags if type_name.blank?

      action_tags(
        type_name,
        api: api,
        type_names: Catalog.new(api: api).type_names,
        tag_suffix: named_action_tag_suffix(registration, api, type_name)
      )
    end
    private_class_method :named_tree_tags

    def named_tree_registration(name, api)
      Catalog.new(api: api).resolved_server&.tool(name)&.registration
    end
    private_class_method :named_tree_registration

    def named_action_tag_suffix(registration, api, type_name)
      return unless registration.target.action?

      Documentation::Openapi::ActionDocs.tag_suffix(registration.target.value, api, type_name)
    end
    private_class_method :named_action_tag_suffix

    def openapi_extras(_entry, tool, surface = nil)
      extras = {}
      tags = tags_for_openapi(tool, surface)
      extras["tags"] = tags if tags.any?
      schema = stringify_schema(tool["outputSchema"])
      extras["outputSchema"] = schema if schema.present?
      extras
    end

    def attach_sidebar!(spec, page, group_tags: nil)
      copy = grouped_tag_copy(page, group_tags: group_tags)
      names = sidebar_tag_order(tool_sidebar_tags(spec) + copy[:intro_tags])
      write_sidebar(spec, page, names, copy[:descriptions])
    end

    def write_sidebar(spec, page, names, descriptions)
      tags = openapi_tags(names, descriptions: descriptions)
      spec["tags"] = tags if tags.any?
      spec["x-tagGroups"] = page.tag_groups if Array(page.tag_groups).any?
      spec
    end
    private_class_method :write_sidebar

    def tool_sidebar_tags(spec)
      Array(spec.dig("x-mcp", "tools")).flat_map { |tool| Array(tool["tags"]) }
    end
    private_class_method :tool_sidebar_tags

    def entry_recordable_type(entry)
      (entry["recordable_type"] || entry[:recordable_type]).to_s
    end
    private_class_method :entry_recordable_type

    def tags_for_openapi(tool, surface)
      found = entry_for_tool(tool, surface)
      return tags_for_entry(found, api: surface&.catalog&.api) if found

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
