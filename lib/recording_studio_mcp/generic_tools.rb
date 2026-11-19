# frozen_string_literal: true

require_relative "generic_tools/definitions"

module RecordingStudioMcp
  module GenericTools
    module_function

    def install(configuration)
      DEFINITIONS.each { |definition| configuration.add_tool(tool_from(definition), override: true) }
    end

    def names
      DEFINITIONS.map { |definition| definition.fetch(:name) }
    end

    def tool_from(definition)
      kind = definition.key?(:operation) ? :operation : :action
      value = (definition[:operation] || definition[:action]).to_sym
      target = Registrations::ToolTarget.new(kind: kind, value: value)
      Registrations::Tool.new(name: definition.fetch(:name).to_s, type: nil, target: target,
                              title: definition.fetch(:title), description: definition.fetch(:description),
                              input: definition.fetch(:input), output: definition.fetch(:output))
    end
    private_class_method :tool_from
  end
end
