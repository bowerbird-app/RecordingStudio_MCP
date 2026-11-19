# frozen_string_literal: true

module RecordingStudioMcp
  module Registrations
    TARGET_KINDS = %i[operation action endpoint].freeze
    OVERRIDE_LOCKED = %i[type target].freeze

    ToolTarget = Data.define(:kind, :value) do
      def operation?
        kind == :operation
      end

      def action?
        kind == :action
      end

      def endpoint?
        kind == :endpoint
      end
    end

    Tool = Data.define(:name, :type, :target, :title, :description, :input, :output) do
      def generic?
        type.nil? && !target.endpoint?
      end
    end

    Type = Data.define(:type, :description)

    Skill = Data.define(:name, :type, :title, :description, :body, :tools, :path, :available_if) do
      def uri
        "skill://#{name}/SKILL.md"
      end
    end

    IncludedTool = Data.define(:name, :title, :description, :allow_sensitive)

    Server = Data.define(:name, :api, :allow_sensitive, :included_tools, :included_skills)
  end
end
