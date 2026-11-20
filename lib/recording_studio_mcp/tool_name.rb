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
      return "list_#{type_plural_snake(type)}" if verb == "list"

      join_action_and_type(verb, type_singular_snake(type))
    end

    def verb_for(action)
      key = action.to_s
      VERBS.fetch(key, key)
    end

    def type_singular_snake(type)
      type_public_token(type).underscore.singularize
    end

    def type_plural_snake(type)
      declared = RecordingStudio.recordable_type_plural_label(type).to_s.parameterize(separator: "_")
      return declared if declared.present?

      type_singular_snake(type).pluralize
    end

    def type_public_token(type)
      name = type.to_s
      (api_public_name(name).presence || name).demodulize
    end

    def api_public_name(type_name)
      return unless RecordingStudioApi.respond_to?(:recordable_registration_for)

      RecordingStudioApi.recordable_registration_for(type_name, api: :public)&.public_name
    end

    def join_action_and_type(verb, type_snake)
      return verb if ends_with_noun?(verb, type_snake)

      remainder = type_snake.split("_").drop(leading_type_overlap(verb, type_snake))
      return verb if remainder.empty?

      "#{verb}_#{remainder.join('_')}"
    end

    def leading_type_overlap(verb, type_snake)
      verb_parts = verb.split("_")
      type_parts = type_snake.split("_")
      max = [verb_parts.length, type_parts.length].min
      max.downto(1) do |count|
        return count if verb_parts.last(count) == type_parts.first(count)
      end
      0
    end

    def ends_with_noun?(verb, type_snake)
      verb == type_snake || verb.end_with?("_#{type_snake}")
    end

    private_class_method :verb_for, :type_singular_snake, :type_plural_snake, :type_public_token,
                         :api_public_name, :join_action_and_type, :leading_type_overlap, :ends_with_noun?
  end
end
