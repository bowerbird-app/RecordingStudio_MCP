# frozen_string_literal: true

module RecordingStudioMcp
  module NamedApi
    DEFAULT = "public"

    module_function

    def normalize(api_key)
      api_key.to_s.presence || DEFAULT
    end

    def public?(api_key)
      normalize(api_key) == DEFAULT
    end

    def known?(api_key)
      key = normalize(api_key)
      return true if key == DEFAULT
      return false unless defined?(RecordingStudioApi)

      Array(RecordingStudioApi.configuration.api_names).map(&:to_s).include?(key)
    end

    def mcp_path(api_key)
      mount = ProtectedResourceMetadata.mcp_mount_path
      public?(api_key) ? mount : "#{mount}/apis/#{normalize(api_key)}"
    end

    def authorization_server_path(api_key)
      mount = ProtectedResourceMetadata.oauth_engine_mount_path
      public?(api_key) ? mount : "#{mount}/apis/#{normalize(api_key)}"
    end

    def well_known_path(api_key)
      "/.well-known/oauth-protected-resource#{mcp_path(api_key)}"
    end

    def from_request(request)
      params = request.respond_to?(:params) ? request.params : nil
      if params.respond_to?(:[]) && params[:api_key].present?
        return normalize(params[:api_key])
      end

      from_path(request.respond_to?(:path) ? request.path : "")
    end

    def from_path(path)
      mount = ProtectedResourceMetadata.mcp_mount_path
      cleaned = path.to_s.sub(%r{/+\z}, "")
      cleaned = "/#{cleaned}" unless cleaned.start_with?("/")
      prefix = "#{mount}/apis/"
      return cleaned.delete_prefix(prefix).split("/", 2).first if cleaned.start_with?(prefix)

      DEFAULT
    end
  end
end
