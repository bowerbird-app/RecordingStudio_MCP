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

    # Two grants share an answer only when their client, access recording,
    # anchor, role, and revoked or trashed state all match. A missing piece
    # stays on the grant object, so an unknown grant never reuses another.
    def cache_key(grant, recording)
      [grant_identity(grant) || grant, recording&.id]
    end

    def grant_identity(grant)
      parts = identity_parts(grant)
      return if parts.nil?

      [:access_grant, *parts]
    end

    def identity_parts(grant)
      client_id = record_id(grant, :api_client)
      access_id = record_id(grant, :access_recording)
      return unless client_id && access_id

      role = read_role(grant)
      state = read_state(grant)
      return if role.nil? || state.nil?

      [client_id, access_id, record_id(grant, :root_recording), role[:role], state[:revoked], state[:trashed]]
    end

    def read_role(grant)
      return { role: grant.role } if grant.respond_to?(:role)

      access = access_recording_for(grant)
      recordable = access.recordable if access.respond_to?(:recordable)
      return { role: recordable.role } if recordable.respond_to?(:role)

      nil
    end

    def read_state(grant)
      access = access_recording_for(grant)
      return if access.nil?

      trashed = trashed_state(access)
      return if trashed.nil?

      { revoked: revoked?(access), trashed: trashed }
    end

    def access_recording_for(grant)
      return unless grant.respond_to?(:access_recording)

      grant.access_recording
    end

    def revoked?(access)
      return true if access.respond_to?(:destroyed?) && access.destroyed?
      return true if access.respond_to?(:revoked?) && access.revoked?

      false
    end

    def trashed_state(access)
      return access.trashed_at.present? if access.respond_to?(:trashed_at)
      return !access.kept? if access.respond_to?(:kept?)

      nil
    end

    def record_id(grant, name)
      return unless grant.respond_to?(name)

      record = grant.public_send(name)
      return unless record.respond_to?(:id)

      record.id.presence
    end
  end
end
