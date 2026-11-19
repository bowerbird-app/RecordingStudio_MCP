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

    def include_tool(name, title: nil, description: nil, allow_sensitive: nil)
      key = name.to_s
      @tools[key] = Registrations::IncludedTool.new(
        name: key,
        title: title,
        description: description,
        allow_sensitive: allow_sensitive
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
  end
end
