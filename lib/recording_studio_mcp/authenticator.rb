# frozen_string_literal: true

module RecordingStudioMcp
  class Authenticator
    Result = Struct.new(:success?, :access_grant, :error, keyword_init: true)

    def self.access_grant(authorization_header)
      new(authorization_header).access_grant
    end

    def initialize(authorization_header)
      @authorization_header = authorization_header.to_s
    end

    def access_grant
      token = bearer_token
      return failure(:missing_token) if token.blank?

      result = RecordingStudioApi.authenticate_authorization_header(
        authorization_header: @authorization_header,
        api: api_for(token)
      )
      return failure(:invalid_token) if result.failure?

      Result.new(success?: true, access_grant: build_access_grant(result.value), error: nil)
    end

    private

    def bearer_token
      scheme, token = @authorization_header.split(" ", 2)
      return if scheme.to_s.casecmp("Bearer").zero? == false

      token.to_s.presence
    end

    def api_for(token)
      RecordingStudioApi.token_authenticators.each do |authenticator|
        resolved = authenticator.call(token: token)
        next if resolved.nil?

        credential = resolved.is_a?(Hash) ? resolved[:credential] : resolved
        api_key = credential&.api_client&.api_key
        return api_key if api_key.present?
      end

      :public
    end

    def build_access_grant(authenticated_client)
      RecordingStudioApi::AccessGrant.new(
        api_client: authenticated_client.api_client,
        credential: authenticated_client.credential,
        access_recording: authenticated_client.access_recording,
        root_recording: authenticated_client.root_recording,
        authorized_by: authenticated_client.authorized_by
      )
    end

    def failure(error)
      Result.new(success?: false, access_grant: nil, error: error)
    end
  end
end
