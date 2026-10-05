# frozen_string_literal: true

module RecordingStudioMcp
  class Connection
    SUBSCRIPTION_ID_META = "io.modelcontextprotocol/subscriptionId"

    attr_reader :id, :protocol_version, :access_grant, :subscription_id

    def initialize(id:, protocol_version:, access_grant:, subscription_id: nil)
      @id = id
      @protocol_version = protocol_version
      @access_grant = access_grant
      @subscription_id = subscription_id
      @uris = Set.new
      @sender = nil
      @mutex = Mutex.new
      @wait = ConditionVariable.new
      @finished = false
    end

    def subscribe(uri)
      @mutex.synchronize { @uris.add(uri.to_s) }
    end

    def unsubscribe(uri)
      @mutex.synchronize { @uris.delete(uri.to_s) }
    end

    def subscribed?(uri)
      @mutex.synchronize { @uris.include?(uri.to_s) }
    end

    def subscribed_uris
      @mutex.synchronize { @uris.to_a }
    end

    def attach_sender(sender)
      @mutex.synchronize { @sender = sender }
    end

    def finish!
      @mutex.synchronize do
        @finished = true
        @wait.broadcast
      end
    end

    def finished?
      @mutex.synchronize { @finished || sender_gone? }
    end

    def wait(timeout: 1)
      @mutex.synchronize do
        @wait.wait(@mutex, timeout) unless @finished || sender_gone?
      end
    end

    def notify_updated(uri)
      sender = sender_for(uri)
      return false if sender.nil?

      sender.write_json(updated_payload(uri))
      true
    rescue *SseWriter::DISCONNECT_ERRORS
      finish!
      false
    end

    def sender_for(uri)
      @mutex.synchronize do
        return if !@uris.include?(uri.to_s) || @finished || @sender.nil? || sender_gone?

        @sender
      end
    end
    private :sender_for

    def acknowledged_payload
      {
        jsonrpc: Protocol::JSONRPC_VERSION,
        method: "notifications/subscriptions/acknowledged",
        params: with_subscription_meta({ notifications: { resourceSubscriptions: subscribed_uris } })
      }
    end

    private

    def updated_payload(uri)
      {
        jsonrpc: Protocol::JSONRPC_VERSION,
        method: "notifications/resources/updated",
        params: with_subscription_meta({ uri: uri })
      }
    end

    def with_subscription_meta(params)
      return params if subscription_id.nil?

      meta = params[:_meta] || {}
      meta = meta.merge(SUBSCRIPTION_ID_META => subscription_id)
      params.merge(_meta: meta)
    end

    def sender_gone?
      sender = @sender
      return false if sender.nil?

      (sender.respond_to?(:disconnected?) && sender.disconnected?) ||
        (sender.respond_to?(:closed?) && sender.closed?)
    end
  end
end
