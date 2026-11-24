# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module_function

    def kept_tag_groups(groups, names)
      Array(groups).filter_map { |group| kept_tag_group(group, names) }
    end

    def kept_tag_group(group, names)
      hash = string_group(group)
      tags = normalized_group_tags(hash, names)
      return if tags.empty?

      hash.merge("tags" => tags)
    end

    def normalized_group_tags(hash, names)
      Array(hash["tags"]).map { |tag| normalize_tag(tag) }.select { |tag| names.include?(tag) }.uniq
    end

    def string_group(group)
      return group.deep_stringify_keys if group.respond_to?(:deep_stringify_keys)

      group.to_h.transform_keys(&:to_s)
    end
    private_class_method :kept_tag_groups, :kept_tag_group, :normalized_group_tags, :string_group
  end
end
