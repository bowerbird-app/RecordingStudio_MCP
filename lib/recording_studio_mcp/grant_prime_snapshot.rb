# frozen_string_literal: true

module RecordingStudioMcp
  # Remembers the anchor, owner, role, and trash state from the moment a grant
  # first builds its scope. Later changes to that recording object do not
  # rewrite the snapshot.
  module GrantPrimeSnapshot
    def accessible_recordings(...)
      capture_prime_snapshot
      super
    end

    def recording_studio_mcp_prime_snapshot
      return unless defined?(@recording_studio_mcp_prime_snapshot)

      @recording_studio_mcp_prime_snapshot
    end

    def self.install!
      return unless defined?(RecordingStudioApi::AccessGrant)

      grant = RecordingStudioApi::AccessGrant
      return if grant.ancestors.include?(self)

      grant.prepend(self)
    end

    private

    def capture_prime_snapshot
      return if defined?(@recording_studio_mcp_prime_snapshot)

      @recording_studio_mcp_prime_snapshot = {
        parent_id: prime_parent_id,
        role: role,
        owner_id: prime_owner_id,
        revoked: prime_revoked?,
        trashed: prime_trashed?
      }.freeze
    end

    def prime_owner_id
      id_of(client_owner) || id_of(actor_owner) || id_of(actor)
    end

    def client_owner
      client = api_client if respond_to?(:api_client)
      return unless client.respond_to?(:owner)

      client.owner
    end

    def actor_owner
      person = actor if respond_to?(:actor)
      return unless person.respond_to?(:owner)

      person.owner
    end

    def id_of(record)
      return unless record.respond_to?(:id)

      record.id.presence
    end

    def prime_parent_id
      access = access_recording
      return if access.nil?

      column = access.parent_recording_id if access.respond_to?(:parent_recording_id)
      return column.presence if column.present?

      parent = access.parent_recording if access.respond_to?(:parent_recording)
      parent.id.presence if parent.respond_to?(:id)
    end

    def prime_revoked?
      access = access_recording
      return true if access.nil?
      return true if access.respond_to?(:destroyed?) && access.destroyed?
      return true if access.respond_to?(:revoked?) && access.revoked?

      false
    end

    def prime_trashed?
      access = access_recording
      return false if access.nil?
      return access.trashed_at.present? if access.respond_to?(:trashed_at)

      access.respond_to?(:kept?) && !access.kept?
    end
  end
end
