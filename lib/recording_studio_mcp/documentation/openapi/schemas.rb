# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module Schemas
        module_function

        def for(page)
          { "TypeName" => Internals.stringify(page.type_schema) }
        end

        def registered_type_description(type_name, api_key)
          full_name = Catalog.new(api: api_key).lookup_type(type_name) || type_name
          openapi = RecordingStudioApi.recordable_registration_for(full_name, api: api_key)&.openapi
          return unless openapi.is_a?(Hash)

          openapi[:description].presence || openapi.dig(:tag, :description).presence
        end
      end
    end
  end
end
