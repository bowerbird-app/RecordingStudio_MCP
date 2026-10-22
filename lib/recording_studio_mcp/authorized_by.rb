# frozen_string_literal: true

module RecordingStudioMcp
  # The event actor stays the OAuth client (or API client). The person who
  # authorized an OAuth token is stored beside that actor, as
  # authorized_by_type and authorized_by_id on the event.
  #
  # Tool calls hand that person and the token's OauthAuthorization to an API
  # action context when the context accepts authorized_by or
  # oauth_authorization. API 0.14.1 accepts neither. Writes that go through
  # record! still receive the keys here when the metadata does not already
  # include them.
  module AuthorizedBy
    HUMAN_KEY = :recording_studio_mcp_authorized_by_human
    STACK_KEY = :recording_studio_mcp_authorized_by_stack
    DEPTH_KEY = :recording_studio_mcp_authorized_by_depth
    METADATA_TYPE = "authorized_by_type"
    METADATA_ID = "authorized_by_id"

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
      stack << current_human
      Thread.current[DEPTH_KEY] = depth + 1
      Thread.current[HUMAN_KEY] = human_for(access_grant)
    end

    def leave
      return if depth.zero?

      Thread.current[DEPTH_KEY] = depth - 1
      Thread.current[HUMAN_KEY] = stack.pop
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

    def context_keywords(context_class, access_grant)
      offered = {
        authorized_by: human_for(access_grant),
        oauth_authorization: oauth_authorization_for(access_grant)
      }
      offered.select { |key, _value| accepts_keyword?(context_class, key) }
    end

    def stamp_payload!(payload)
      human = current_human
      return if human.nil?

      metadata = payload_metadata(payload)
      return if metadata.nil? || metadata.frozen?
      return if metadata_has?(metadata, METADATA_TYPE)

      metadata[METADATA_TYPE] = type_name(human)
      metadata[METADATA_ID] = human.id.to_s
    end

    def accepts_keyword?(context_class, key)
      context_class.instance_method(:initialize).parameters.any? do |type, name|
        type == :keyrest || (%i[key keyreq].include?(type) && name == key)
      end
    rescue NameError
      false
    end

    def current_human
      Thread.current[HUMAN_KEY]
    end

    def stack
      Thread.current[STACK_KEY] ||= []
    end

    def depth
      Thread.current[DEPTH_KEY].to_i
    end

    def payload_metadata(payload)
      return unless payload.is_a?(Hash)
      return payload[:metadata] if payload.key?(:metadata)

      payload["metadata"] if payload.key?("metadata")
    end

    def metadata_has?(metadata, key)
      metadata.key?(key) || metadata.key?(key.to_sym)
    end

    def type_name(human)
      klass = human.class
      return klass.polymorphic_name if klass.respond_to?(:polymorphic_name)

      klass.name
    end

    def mutex
      @mutex ||= Mutex.new
    end
  end
end
