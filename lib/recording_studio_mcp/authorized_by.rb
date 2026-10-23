# frozen_string_literal: true

module RecordingStudioMcp
  # Event actor stays the OAuth client. authorized_by_type and authorized_by_id
  # record who authorized the token. Sign-in passes authorized_by into AccessGrant
  # when that keyword exists. Otherwise the stamp reads OauthAuthorization#manager_actor.
  # record! strips client-sent authorized_by keys on that client's writes, then stores
  # authorized_by when one is present. The stamp clears when the tool call ends.
  module AuthorizedBy
    AUTHORIZED_BY_KEY = :recording_studio_mcp_authorized_by
    CLIENT_KEY = :recording_studio_mcp_authorized_by_client
    STACK_KEY = :recording_studio_mcp_authorized_by_stack
    DEPTH_KEY = :recording_studio_mcp_authorized_by_depth
    RESERVED_METADATA_KEYS = %i[authorized_by_type authorized_by_id].freeze

    module_function

    def install!
      return if @installed
      return unless defined?(RecordingStudio::Hooks)

      mutex.synchronize do
        return if @installed

        RecordingStudio.configuration.hooks.before_record { |payload| stamp_payload!(payload) }
        @installed = true
      end
    end

    def enter(access_grant)
      install!
      stack << [current_authorized_by, current_client]
      Thread.current[DEPTH_KEY] = depth + 1
      Thread.current[AUTHORIZED_BY_KEY] = authorized_by_for(access_grant)
      Thread.current[CLIENT_KEY] = client_for(access_grant)
    end

    def leave
      return if depth.zero?

      Thread.current[DEPTH_KEY] = depth - 1
      authorized_by, client = Array(stack.pop)
      Thread.current[AUTHORIZED_BY_KEY] = authorized_by
      Thread.current[CLIENT_KEY] = client
    end

    def authorized_by_for(access_grant)
      actor = if access_grant.respond_to?(:authorized_by)
                access_grant.authorized_by
              else
                manager_actor_for(access_grant)
              end
      actor if actor && actor.id.present?
    end

    def manager_actor_for(access_grant)
      authorization = oauth_authorization_for(access_grant)
      authorization.manager_actor if authorization.respond_to?(:manager_actor)
    end

    def oauth_authorization_for(access_grant)
      return unless access_grant.respond_to?(:credential)

      credential = access_grant.credential
      credential.oauth_authorization if credential.respond_to?(:oauth_authorization)
    end

    def stamp_payload!(payload)
      client = current_client
      return if client.nil?
      return unless oauth_client_write?(payload, client)

      metadata = payload_metadata(payload)
      return if metadata.nil? || metadata.frozen?

      strip_reserved!(metadata)
      actor = current_authorized_by
      return if actor.nil?

      metadata[:authorized_by_type] = type_name(actor)
      metadata[:authorized_by_id] = actor.id
    end

    def current_authorized_by = Thread.current[AUTHORIZED_BY_KEY]

    def current_client = Thread.current[CLIENT_KEY]

    def stack = (Thread.current[STACK_KEY] ||= [])

    def depth = Thread.current[DEPTH_KEY].to_i

    def client_for(access_grant)
      return unless access_grant.respond_to?(:api_client)

      access_grant.api_client
    end

    def oauth_client_write?(payload, client)
      actor = payload_actor(payload)
      return false if actor.nil?
      return true if actor.equal?(client)

      same_record?(actor, client)
    end

    def same_record?(actor, client)
      return false unless actor.instance_of?(client.class)
      return false unless actor.respond_to?(:id) && client.respond_to?(:id)

      identifier = actor.id
      !identifier.nil? && identifier == client.id
    end

    def payload_actor(payload)
      return unless payload.is_a?(Hash)
      return payload[:actor] if payload.key?(:actor)

      payload["actor"] if payload.key?("actor")
    end

    def payload_metadata(payload)
      return unless payload.is_a?(Hash)
      return payload[:metadata] if payload.key?(:metadata)

      payload["metadata"] if payload.key?("metadata")
    end

    def strip_reserved!(metadata)
      RESERVED_METADATA_KEYS.each do |key|
        metadata.delete(key)
        metadata.delete(key.to_s)
      end
    end

    def type_name(actor)
      klass = actor.class
      return klass.polymorphic_name if klass.respond_to?(:polymorphic_name)

      klass.name
    end

    def mutex = (@mutex ||= Mutex.new)
  end
end
