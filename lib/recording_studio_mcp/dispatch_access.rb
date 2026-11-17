# frozen_string_literal: true

module RecordingStudioMcp
  # Access answers for one fan-out. The hash dies with this object.
  class DispatchAccess
    def initialize
      @answers = {}
    end

    def allowed?(grant, recording, uri:)
      key = cache_key(grant, recording)
      return @answers[key] if @answers.key?(key)

      @answers[key] = scope_allows?(grant, recording, uri)
    end

    private

    def scope_allows?(grant, recording, uri)
      return Resources.accessible?(grant, uri) if recording.nil?

      scope = Resources.accessible_scope(grant)
      return false if scope.nil?

      scope.exists?(id: recording.id)
    end

    # Same client and access recording means the same grant. The root id is
    # only there so two anchors are not treated as one grant. The scope query
    # above is still what decides access.
    def cache_key(grant, recording)
      client_id = record_id(grant, :api_client)
      access_id = record_id(grant, :access_recording)
      identity = if client_id && access_id
                   [:access_grant, client_id, access_id, record_id(grant, :root_recording)]
                 else
                   grant
                 end
      [identity, recording&.id]
    end

    def record_id(grant, name)
      return unless grant.respond_to?(name)

      record = grant.public_send(name)
      return unless record.respond_to?(:id)

      record.id.presence
    end
  end
end
