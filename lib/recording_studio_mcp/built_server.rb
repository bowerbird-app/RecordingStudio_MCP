# frozen_string_literal: true

module RecordingStudioMcp
  BuiltServer = Data.define(
    :name,
    :api,
    :allow_sensitive,
    :tools,
    :types,
    :skills,
    :filters
  ) do
    def tool(name)
      tools[name.to_s]
    end

    def tool?(name)
      name.to_s == "describe" || tools.key?(name.to_s)
    end

    def type_names
      types.keys
    end

    def skill_names
      skills.keys
    end
  end

  BuiltTool = Data.define(
    :name,
    :registration,
    :title,
    :description,
    :allow_sensitive,
    :sensitive,
    :lookup,
    :metric,
    :family
  )
end
