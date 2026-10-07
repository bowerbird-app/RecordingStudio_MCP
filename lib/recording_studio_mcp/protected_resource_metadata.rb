# frozen_string_literal: true

module RecordingStudioMcp
  module ProtectedResourceMetadata
    module_function

    def document(request, api_key: nil)
      key = NamedApi.normalize(api_key || NamedApi.from_request(request))
      {
        resource: resource_identifier(request, api_key: key),
        authorization_servers: [authorization_server_issuer(request, api_key: key)],
        bearer_methods_supported: ["header"]
      }
    end

    def resource_identifier(request, api_key: NamedApi::DEFAULT)
      "#{request.base_url}#{NamedApi.mcp_path(api_key)}"
    end

    def authorization_server_issuer(request, api_key: NamedApi::DEFAULT)
      "#{request.base_url}#{NamedApi.authorization_server_path(api_key)}"
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

    def well_known_path(api_key: NamedApi::DEFAULT)
      path = if NamedApi.public?(api_key)
               RecordingStudioMcp.configuration.oauth_protected_resource_path.to_s
             else
               ""
             end
      path = NamedApi.well_known_path(api_key) if path.blank?
      path = "/#{path}" unless path.start_with?("/")
      path
    end
  end
end
