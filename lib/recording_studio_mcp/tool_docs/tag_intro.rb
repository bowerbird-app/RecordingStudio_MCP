# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module_function

    def grouped_tag_copy(page, group_tags:)
      prose = {}
      lines = {}
      fill_tag_buckets(page, group_tags, prose, lines)
      { descriptions: joined_tag_copy(prose, lines), intro_tags: lines.keys }
    end
    private_class_method :grouped_tag_copy

    def fill_tag_buckets(page, group_tags, prose, lines)
      state = tag_state(page, group_tags)
      Array(page.types).each do |entry|
        assign_type_tag_description(prose, entry, page, group_tags)
        collect_core_lines(lines, entry, state)
      end
    end
    private_class_method :fill_tag_buckets

    def tag_state(page, group_tags)
      {
        page: page,
        group_tags: group_tags,
        context: Documentation::Openapi::TypeOperationLines.context_for(page),
        type_names: page_type_names(page)
      }
    end
    private_class_method :tag_state

    def page_type_names(page)
      Array(page.types).map { |entry| entry_recordable_type(entry) }
    end
    private_class_method :page_type_names

    def collect_core_lines(lines, entry, state)
      shown = string_keyed(entry)
      type_name = entry_recordable_type(shown)
      return if type_name.blank?

      core = core_lines_for(shown, type_name, state)
      return if core.empty?

      tags_for_type(shown, type_name, state).each { |tag| lines[tag] = Array(lines[tag]) + core }
    end
    private_class_method :collect_core_lines

    def string_keyed(entry)
      entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : entry
    end
    private_class_method :string_keyed

    def core_lines_for(entry, type_name, state)
      Documentation::Openapi::TypeOperationLines.lines_for(
        entry, entry["type"].to_s, type_name, state[:context]
      )
    end
    private_class_method :core_lines_for

    def tags_for_type(entry, type_name, state)
      return action_tags_for(type_name, state) if capability_actions?(entry)

      shared_group_tags(type_name, state[:page].api_key)
    end
    private_class_method :tags_for_type

    def capability_actions?(entry)
      Array(entry["capability_actions"]).any?
    end
    private_class_method :capability_actions?

    def action_tags_for(type_name, state)
      action_tags(
        type_name,
        api: state[:page].api_key,
        group_tags: state[:group_tags],
        type_names: state[:type_names]
      )
    end
    private_class_method :action_tags_for

    # A type with no capability actions gets no page of its own. Its core lines
    # go on a shared OpenAPI tag group when that group is a different name.
    def shared_group_tags(type_name, api_key)
      openapi = type_registration(type_name, api_key)&.openapi
      return [] unless openapi.is_a?(Hash)

      group = openapi_group(openapi)
      return [] if group.blank? || openapi_tag_names(openapi).include?(group)

      [normalize_tag(group)]
    end
    private_class_method :shared_group_tags

    def openapi_group(openapi)
      tag = openapi[:tag] || openapi["tag"]
      return "" unless tag.is_a?(Hash)

      (tag[:group] || tag["group"]).to_s
    end
    private_class_method :openapi_group

    def openapi_tag_names(openapi)
      Array(openapi[:tags] || openapi["tags"]).map(&:to_s)
    end
    private_class_method :openapi_tag_names

    def joined_tag_copy(prose, lines)
      (prose.keys | lines.keys).each_with_object({}) do |tag, copy|
        text = [prose[tag], *Array(lines[tag])].compact.reject(&:blank?).join("\n\n")
        copy[tag] = text if text.present?
      end
    end
    private_class_method :joined_tag_copy
  end
end
