# frozen_string_literal: true

module RecordingStudioMcp
  module ToolDocs
    module_function

    def endpoint_tags(endpoint, api: nil)
      listed_tags(endpoint).presence ||
        endpoint_group_names(endpoint, api).presence ||
        endpoint_owner_tags(endpoint, api).presence ||
        [OTHER_TOOLS_TAG]
    end

    def action_tags(type_name, api:, group_tags: nil, type_names: [], tag_suffix: nil)
      tags = owner_tags(type_name, api: api, group_tags: group_tags, type_names: type_names)
      suffix_tags(tags, tag_suffix)
    end

    def sidebar_tag_order(names)
      unique = Array(names).map(&:to_s).reject(&:blank?).uniq
      other = unique.delete(OTHER_TOOLS_TAG)
      ordered = unique.sort
      ordered.push(OTHER_TOOLS_TAG) if other
      ordered
    end

    def listed_tags(source)
      raw = explicit_tag_list(source)
      return [] if raw.nil?

      Array(raw).map(&:to_s).reject { |name| ignored_tag?(name) }.uniq
    end
    private_class_method :listed_tags

    def explicit_tag_list(source)
      openapi = source&.openapi
      return unless openapi.is_a?(Hash)
      return unless openapi.key?(:tags) || openapi.key?("tags")

      openapi[:tags] || openapi["tags"]
    end
    private_class_method :explicit_tag_list

    def ignored_tag?(name)
      name.blank? || IGNORED_TAGS.include?(name)
    end
    private_class_method :ignored_tag?

    def endpoint_group_names(endpoint, api)
      return [] if api.nil?

      group = endpoint.openapi&.dig(:tag, :group)
      return [] if group.blank?

      Array(endpoint_group_tags(api: api)[group.to_s]) - IGNORED_TAGS
    end
    private_class_method :endpoint_group_names

    def endpoint_owner_tags(endpoint, api)
      type_name = endpoint.recordable_type
      return [] if type_name.blank? || api.nil?

      owner_tags(type_name, api: api)
    end
    private_class_method :endpoint_owner_tags

    def suffix_tags(tags, suffix)
      text = suffix.to_s.strip
      return tags if text.empty?

      tags.map { |tag| "#{tag} #{text}" }
    end
    private_class_method :suffix_tags

    def owner_tags(type_name, api:, group_tags: nil, type_names: [])
      tags = type_tags(type_name, api: api, group_tags: group_tags)
      return tags if tags.any?

      inherited = namespaced_action_tags(type_name, api: api, group_tags: group_tags, type_names: type_names)
      return inherited if inherited.any?

      [owner_tag_name(type_name, api)]
    end
    private_class_method :owner_tags

    def owner_tag_name(type_name, api)
      name = public_type_name(type_name, api)
      ignored_tag?(name) ? OTHER_TOOLS_TAG : name
    end
    private_class_method :owner_tag_name

    def public_type_name(type_name, api)
      registration = type_registration(type_name, api)
      name = registration.public_name.to_s if registration
      name.presence || type_name.to_s.demodulize
    end
    private_class_method :public_type_name
  end
end
