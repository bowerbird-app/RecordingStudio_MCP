# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module ActionDocs
        module_function

        def raw_copy(action)
          openapi = action&.openapi
          return {} unless openapi.is_a?(Hash)

          %w[title summary description].each_with_object({}) do |key, fields|
            value = openapi[key.to_sym].presence || openapi[key].presence
            fields[key] = value if value
          end
        end

        def title(action_name, api_key)
          documented = raw_copy(RecordingStudioApi.capability_action(action_name, api: api_key))["title"]
          documented.presence || action_name.humanize.titleize
        end

        def disambiguate_titles(tools)
          tools.group_by { |tool| Array(tool["tags"]).join("\0") }.each_value do |group|
            disambiguate_group(group)
          end
          tools
        end

        def disambiguate_group(group)
          counts = group.map { |tool| tool["title"].to_s }.tally
          group.each do |tool|
            next unless counts[tool["title"].to_s] > 1

            tool["title"] = title_with_type_label(tool)
          end
        end
        private_class_method :disambiguate_group

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

        def title_with_type_label(tool)
          type_name = tool["name"].to_s.split("--", 2).first
          label = RecordingStudio.recordable_type_label(type_name)
          words = tool["title"].to_s.split
          rest = words.drop(1).join(" ")
          [words.first, label, rest].reject(&:blank?).join(" ")
        end
        private_class_method :title_with_type_label

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
        private_class_method :definition_fields

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
