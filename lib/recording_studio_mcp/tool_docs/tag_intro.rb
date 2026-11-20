# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module_function

    def grouped_tag_copy(page, group_tags:)
      descriptions = type_tag_sections(page, group_tags)
      { descriptions: descriptions, intro_tags: descriptions.keys }
    end
    private_class_method :grouped_tag_copy

    def type_tag_sections(page, group_tags)
      state = tag_state(page, group_tags)
      grouped = grouped_type_entries(page, state)
      grouped.each_with_object({}) do |(tag, entries), copy|
        texts = type_sections_for(entries, state)
        copy[tag] = texts.join("\n\n") if texts.any?
      end
    end
    private_class_method :type_tag_sections

    def grouped_type_entries(page, state)
      Array(page.types).each_with_object({}) do |entry, grouped|
        shown = string_keyed(entry)
        type_name = entry_recordable_type(shown)
        next if type_name.blank?

        tags_for_type(type_name, state).each do |tag|
          grouped[tag] = Array(grouped[tag]) << shown
        end
      end
    end
    private_class_method :grouped_type_entries

    def type_sections_for(entries, state)
      prefix = entries.size > 1
      entries.filter_map do |entry|
        text = Documentation::Openapi::TypeOperationLines.section_for(
          entry, entry["type"].to_s, entry_recordable_type(entry), state[:context]
        )
        next if text.blank?

        prefix ? "Type: `#{entry['type']}`\n\n#{text}" : text
      end
    end
    private_class_method :type_sections_for

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

    def string_keyed(entry)
      entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : entry
    end
    private_class_method :string_keyed

    def tags_for_type(type_name, state)
      action_tags(
        type_name,
        api: state[:page].api_key,
        group_tags: state[:group_tags],
        type_names: state[:type_names]
      )
    end
    private_class_method :tags_for_type
  end
end
