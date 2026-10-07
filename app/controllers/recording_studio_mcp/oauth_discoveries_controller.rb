# frozen_string_literal: true

module RecordingStudioMcp
  class OauthDiscoveriesController < ActionController::API
    def protected_resource
      api_key = NamedApi.from_request(request)
      return head :not_found unless NamedApi.known?(api_key)

      render json: ProtectedResourceMetadata.document(request, api_key: api_key)
    end
  end
end
