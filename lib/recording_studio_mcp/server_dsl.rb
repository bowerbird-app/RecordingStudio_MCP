# frozen_string_literal: true

module RecordingStudioMcp
  class ServerDsl
    def initialize
      @tools = {}
      @skills = []
    end

    def include_tools(*names)
      names.flatten.each { |name| include_tool(name) }
      nil
    end

    def include_tool(name, title: nil, description: nil, allow_sensitive: nil, filter: nil, filters: nil)
      key = name.to_s
      @tools[key] = Registrations::IncludedTool.new(
        name: key,
        title: title,
        description: description,
        allow_sensitive: allow_sensitive,
        filters: stringify_filters(filter || filters)
      )
      nil
    end

    def include_skills(*names)
      names.flatten.each { |name| @skills << name.to_s }
      @skills.uniq!
      nil
    end

    def included_tools
      @tools.values
    end

    def included_skills
      @skills.dup
    end

    private

    def stringify_filters(value)
      return {} if value.blank?
      raise ArgumentError, "filter must be an object" unless value.respond_to?(:to_h)

      value.to_h.transform_keys(&:to_s).transform_values { |entry| entry.respond_to?(:to_h) ? entry.to_h : entry }
    end
  end
end
