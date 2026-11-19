# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module ActionDocs
        module_function

        def raw_copy(action)
          copy_from(action&.openapi)
        end

        def copy_for(action, type_name)
          return {} if action.nil?

          copy_from(action.openapi).merge(copy_from(typed_openapi(action, type_name)))
        end

        def copy_from(openapi)
          return {} unless openapi.is_a?(Hash)

          %w[title summary description].each_with_object({}) do |key, fields|
            value = openapi[key.to_sym].presence || openapi[key].presence
            fields[key] = value if value
          end
        end
        private_class_method :copy_from

        def title(action_name, api_key, type_name)
          documented = documented_title(action_name, api_key, type_name)
          return documented if documented.present?

          label = RecordingStudio.recordable_type_label(type_name).to_s.singularize
          "#{label} - #{action_name.to_s.humanize.titleize}"
        end

        def tag_suffix(action_name, api_key, type_name)
          action = RecordingStudioApi.capability_action(action_name, api: api_key)
          return if action.nil?

          openapi_value(typed_openapi(action, type_name), "tag_suffix")
        end

        def documented_title(action_name, api_key, type_name)
          action = RecordingStudioApi.capability_action(action_name, api: api_key)
          return if action.nil?

          per_type = openapi_value(typed_openapi(action, type_name), "title")
          per_type.presence || raw_copy(action)["title"]
        end
        private_class_method :documented_title

        def typed_openapi(action, type_name)
          action.openapi_for(type: type_name, action: action.name)
        end
        private_class_method :typed_openapi

        def openapi_value(openapi, key)
          return unless openapi.is_a?(Hash)

          openapi[key.to_sym].presence || openapi[key].presence
        end
        private_class_method :openapi_value

        def schema(definition)
          built = EndpointSchema.build(contract_endpoint(definition))
          apply_allow_blank(built, definition)
          built
        end

        def example(properties)
          properties.each_with_object({}) do |(name, property), acc|
            acc[name.to_s] = example_value(name, property)
          end
        end

        def contract_endpoint(definition)
          RecordingStudioApi::RegisteredEndpoint.new(
            name: :contract,
            http_verb: :post,
            path: "contract",
            handler: ->(*) { {} },
            input_contract: definition
          )
        end
        private_class_method :contract_endpoint

        def apply_allow_blank(schema, definition)
          fields = definition_fields(definition)
          properties = schema[:properties]
          return schema unless fields && properties

          fields.each { |name, rules| stamp_min_length(properties, name, rules) }
          schema
        end
        private_class_method :apply_allow_blank

        def stamp_min_length(properties, name, rules)
          return unless rules.to_h.deep_symbolize_keys[:allow_blank] == false

          property = properties[name.to_sym] || properties[name.to_s]
          return unless property && (property[:type] || property["type"]).to_s == "string"

          property[:minLength] = 1
        end
        private_class_method :stamp_min_length

        def definition_fields(definition)
          return unless definition.respond_to?(:to_h)

          hash = definition.to_h
          hash[:fields] || hash["fields"]
        end

        def example_value(name, property)
          property = Internals.stringify(property)
          return property["enum"].first if Array(property["enum"]).any?

          case property["type"].to_s
          when "integer" then 1
          when "number" then 1.0
          when "boolean" then true
          when "array" then []
          when "object" then {}
          else name.to_s
          end
        end
        private_class_method :example_value
      end
    end
  end
end
