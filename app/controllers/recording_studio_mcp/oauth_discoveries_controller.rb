# frozen_string_literal: true

module RecordingStudioMcp
  class OauthDiscoveriesController < ActionController::API
    def protected_resource
      render json: ProtectedResourceMetadata.document(request)
    end
  end
end
