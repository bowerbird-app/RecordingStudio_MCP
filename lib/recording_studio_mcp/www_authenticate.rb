# frozen_string_literal: true

module RecordingStudioMcp
  module WwwAuthenticate
    module_function

    def header_value(request, error: nil)
      parts = [%(Bearer resource_metadata="#{resource_metadata_url(request)}")]
      parts << %(error="#{error}") if error.present?
      parts.join(", ")
    end

    def resource_metadata_url(request)
      "#{request.base_url}#{ProtectedResourceMetadata.well_known_path}"
    end
  end
end
