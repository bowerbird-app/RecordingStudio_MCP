# frozen_string_literal: true

module RecordingStudioMcp
  # Event actor stays the OAuth client. The person who authorized the token
  # is authorized_by_type and authorized_by_id on the event.
  #
  # API 0.16 reads AccessGrant#authorized_by from the grant MCP already
  # passes. Those constructors do not take authorized_by.
  #
  # record! during a tool call strips client-sent authorized_by keys from
  # writes whose actor is that token's API client. An OAuth grant then stores
  # the server human. A client-credentials grant has no human, so the keys
  # stay absent. The stamp is thread-local and cleared when the tool call ends.
  module AuthorizedBy
    HUMAN_KEY = :recording_studio_mcp_authorized_by_human
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
      stack << [current_human, current_client]
      Thread.current[DEPTH_KEY] = depth + 1
      Thread.current[HUMAN_KEY] = human_for(access_grant)
      Thread.current[CLIENT_KEY] = client_for(access_grant)
    end

    def leave
      return if depth.zero?

      Thread.current[DEPTH_KEY] = depth - 1
      human, client = Array(stack.pop)
      Thread.current[HUMAN_KEY] = human
      Thread.current[CLIENT_KEY] = client
    end

    def human_for(access_grant)
      authorization = oauth_authorization_for(access_grant)
      return unless authorization.respond_to?(:manager_actor)

      human = authorization.manager_actor
      return if human.nil? || human.id.blank?

      human
    end

    def oauth_authorization_for(access_grant)
      return if access_grant.nil?
      return unless access_grant.respond_to?(:credential)

      credential = access_grant.credential
      return if credential.nil?
      return unless credential.respond_to?(:oauth_authorization)

      credential.oauth_authorization
    end

    def stamp_payload!(payload)
      client = current_client
      return if client.nil?
      return unless oauth_client_write?(payload, client)

      metadata = payload_metadata(payload)
      return if metadata.nil? || metadata.frozen?

      strip_reserved!(metadata)
      human = current_human
      return if human.nil?

      metadata[:authorized_by_type] = type_name(human)
      metadata[:authorized_by_id] = human.id
    end

    def current_human = Thread.current[HUMAN_KEY]

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

    def type_name(human)
      klass = human.class
      return klass.polymorphic_name if klass.respond_to?(:polymorphic_name)

      klass.name
    end

    def mutex = (@mutex ||= Mutex.new)
  end
end
