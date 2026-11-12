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
          openapi = RecordingStudioApi.recordable_registration_for(type_name, api: api_key)&.openapi
          return unless openapi.is_a?(Hash)

          openapi[:description].presence || openapi.dig(:tag, :description).presence
        end
      end
    end
  end
end
