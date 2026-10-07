# frozen_string_literal: true

module RecordingStudioMcp
  module WwwAuthenticate
    module_function

    def header_value(request, error: nil, api_key: nil)
      key = NamedApi.normalize(api_key || NamedApi.from_request(request))
      parts = [%(Bearer resource_metadata="#{resource_metadata_url(request, api_key: key)}")]
      parts << %(error="#{error}") if error.present?
      parts.join(", ")
    end

    def resource_metadata_url(request, api_key: NamedApi::DEFAULT)
      "#{request.base_url}#{ProtectedResourceMetadata.well_known_path(api_key: api_key)}"
    end
  end
end
