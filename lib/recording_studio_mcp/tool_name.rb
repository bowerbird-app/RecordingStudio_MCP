# frozen_string_literal: true

module RecordingStudioMcp
  module ToolName
    VERBS = {
      "index" => "list",
      "list" => "list",
      "show" => "show",
      "create" => "create",
      "update" => "update",
      "destroy" => "delete",
      "delete" => "delete"
    }.freeze

    module_function

    def call(type, action)
      verb = verb_for(action)
      type_snake = type_singular_snake(type)
      return "list_#{type_plural_snake(type)}" if verb == "list"
      return verb if ends_with_noun?(verb, type_snake)

      "#{verb}_#{type_snake}"
    end

    def verb_for(action)
      key = action.to_s
      VERBS.fetch(key, key)
    end

    def type_singular_snake(type)
      type_public_token(type).underscore.singularize
    end

    def type_plural_snake(type)
      token = type_public_token(type)
      declared = declared_plural_snake(token)
      return declared if declared.present?

      token.underscore.singularize.pluralize
    end

    def type_public_token(type)
      name = type.to_s
      (api_public_name(name).presence || name).demodulize
    end

    def api_public_name(type_name)
      return unless defined?(RecordingStudioApi)
      return unless RecordingStudioApi.respond_to?(:recordable_registration_for)
      return unless RecordingStudioApi.instance_variable_defined?(:@configuration)

      RecordingStudioApi.recordable_registration_for(type_name, api: :public)&.public_name
    end

    def declared_plural_snake(token)
      return unless defined?(RecordingStudio)
      return unless RecordingStudio.respond_to?(:recordable_declaration_for)

      declaration = RecordingStudio.recordable_declaration_for(token)
      return if declaration.nil? || !declaration.respond_to?(:plural_label)

      parameterize_label(declaration.plural_label)
    end

    def parameterize_label(label)
      text = label.to_s.strip
      return if text.blank?

      text.parameterize(separator: "_").presence
    end

    def ends_with_noun?(verb, type_snake)
      verb == type_snake || verb.end_with?("_#{type_snake}")
    end

    class << self
      private :verb_for, :type_singular_snake, :type_plural_snake, :type_public_token,
              :api_public_name, :declared_plural_snake, :parameterize_label, :ends_with_noun?
    end
  end
end
