# frozen_string_literal: true

module RecordingStudioMcp
  class DocumentationConfiguration
    attr_accessor :enabled, :access, :layout_name

    def initialize
      @enabled = false
      @access = nil
      @layout_name = nil
    end

    def to_h
      {
        documentation_enabled: enabled,
        documentation_access: access.respond_to?(:call) ? :callable : access,
        documentation_layout_name: layout_name
      }
    end

    def validate!
      return unless enabled
      return if %i[public authenticated].include?(access) || access.respond_to?(:call)

      raise ArgumentError,
            "documentation_access must be public, authenticated, or callable when documentation is enabled"
    end
  end
end
