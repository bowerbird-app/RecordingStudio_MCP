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
      path = RecordingStudioMcp.configuration.oauth_protected_resource_path.to_s
      path = "/.well-known/oauth-protected-resource" if path.blank?
      path = "/#{path}" unless path.start_with?("/")
      "#{request.base_url}#{path}"
    end
  end
end
