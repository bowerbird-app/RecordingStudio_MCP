# frozen_string_literal: true

require_relative "registry/skills"

module RecordingStudioMcp
  module Registry
    include Skills

    def register_tool(name:, title:, description:, **)
      configuration.add_tool(tool_registration(name: name, title: title, description: description, **))
    end

    def register_type(type:, description:)
      configuration.add_type(Registrations::Type.new(type: type.to_s, description: description.to_s))
    end

    def register_server(name, api:, allow_sensitive: false, &block)
      dsl = ServerDsl.new
      dsl.instance_eval(&block) if block
      configuration.add_server(server_registration(name, api, allow_sensitive, dsl))
    end

    private

    def server_registration(name, api, allow_sensitive, dsl)
      Registrations::Server.new(
        name: name.to_s,
        api: api,
        allow_sensitive: allow_sensitive,
        included_tools: dsl.included_tools,
        included_skills: dsl.included_skills
      )
    end

    def tool_registration(name:, title:, description:, **options)
      Registrations::Tool.new(
        name: name.to_s,
        type: options[:type]&.to_s,
        target: tool_target(**options.slice(:operation, :action, :endpoint)),
        title: title.to_s,
        description: description.to_s,
        input: stringify_tool_input(options[:input]),
        output: options[:output]
      )
    end

    def tool_target(operation: nil, action: nil, endpoint: nil)
      kinds = { operation: operation, action: action, endpoint: endpoint }.compact
      raise ArgumentError, "register_tool requires exactly one of operation, action, or endpoint" unless kinds.one?

      kind, value = kinds.first
      Registrations::ToolTarget.new(kind: kind, value: value.to_sym)
    end

    def stringify_tool_input(input)
      return {} if input.blank?
      raise ArgumentError, "input must be an object" unless input.respond_to?(:to_h)

      input.to_h.to_h { |field, meta| stringify_input_field(field, meta) }
    end

    def stringify_input_field(field, meta)
      raise ArgumentError, "input #{field} must be an object" unless meta.respond_to?(:to_h)

      [field.to_s, meta.to_h.transform_keys(&:to_sym)]
    end
  end
end
