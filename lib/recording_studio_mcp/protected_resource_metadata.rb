# frozen_string_literal: true

module RecordingStudioMcp
  module ProtectedResourceMetadata
    module_function

    def document(request)
      {
        resource: resource_identifier(request),
        authorization_servers: [authorization_server_issuer(request)],
        bearer_methods_supported: ["header"]
      }
    end

    def resource_identifier(request)
      "#{request.base_url}#{mcp_mount_path}"
    end

    def authorization_server_issuer(request)
      "#{request.base_url}#{oauth_engine_mount_path}"
    end

    def mcp_mount_path
      path = RecordingStudioMcp.configuration.mcp_mount_path.to_s
      path = "/recording_studio_mcp" if path.blank?
      path = "/#{path}" unless path.start_with?("/")
      path.chomp("/")
    end

    def oauth_engine_mount_path
      path = RecordingStudioMcp.configuration.oauth_engine_mount_path.to_s
      path = "/recording_studio_oauth" if path.blank?
      path = "/#{path}" unless path.start_with?("/")
      path.chomp("/")
    end

    def well_known_path
      path = RecordingStudioMcp.configuration.oauth_protected_resource_path.to_s
      if path.blank?
        path = "/.well-known/oauth-protected-resource#{mcp_mount_path}"
      end
      path = "/#{path}" unless path.start_with?("/")
      path
    end
  end
end
