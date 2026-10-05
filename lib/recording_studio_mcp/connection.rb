# frozen_string_literal: true

require "timeout"

module RecordingStudioMcp
  class Connection
    SUBSCRIPTION_ID_META = "io.modelcontextprotocol/subscriptionId"
    QUEUE_LIMIT = 32
    WRITE_TIMEOUT_SECONDS = 1

    attr_reader :id, :protocol_version, :access_grant, :subscription_id

    def initialize(id:, protocol_version:, access_grant:, subscription_id: nil)
      @id = id
      @protocol_version = protocol_version
      @access_grant = access_grant
      @subscription_id = subscription_id
      @uris = Set.new
      @queue = OutboundQueue.new(limit: QUEUE_LIMIT)
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
        @wait.wait(@mutex, timeout) unless @finished || @queue.any?
      end
    end

    def pending?
      @mutex.synchronize { @queue.any? }
    end

    def enqueue_updated(uri) # rubocop:disable Naming/PredicateMethod
      @mutex.synchronize { store_update(uri) } == :ok
    end

    def shift_pending(timeout: 1)
      @mutex.synchronize do
        @wait.wait(@mutex, timeout) if @queue.empty? && !@finished
        @queue.shift
      end
    end

    def write_payload(writer, payload)
      Timeout.timeout(WRITE_TIMEOUT_SECONDS) { writer.write_json(payload) }
      true
    rescue Timeout::Error, *SseWriter::DISCONNECT_ERRORS
      finish!
      false
    end

    def acknowledged_payload
      {
        jsonrpc: Protocol::JSONRPC_VERSION,
        method: "notifications/subscriptions/acknowledged",
        params: with_subscription_meta({ notifications: { resourceSubscriptions: subscribed_uris } })
      }
    end

    # https://modelcontextprotocol.io/specification/2026-07-28/schema — SubscriptionsListenResult
    def listen_completion_payload
      {
        jsonrpc: Protocol::JSONRPC_VERSION,
        id: subscription_id,
        result: ResultShape.complete(
          { _meta: { SUBSCRIPTION_ID_META => subscription_id } },
          protocol_version: protocol_version,
          cacheable: false
        )
      }
    end

    private

    def store_update(uri)
      return :rejected if @finished || !@uris.include?(uri.to_s)

      if @queue.push(updated_payload(uri)) == :full
        @finished = true
        @wait.broadcast
        return :full
      end

      @wait.broadcast
      :ok
    end

    def updated_payload(uri)
      {
        jsonrpc: Protocol::JSONRPC_VERSION,
        method: "notifications/resources/updated",
        params: with_subscription_meta({ uri: uri })
      }
    end

    def with_subscription_meta(params)
      return params if subscription_id.nil?

      meta = (params[:_meta] || {}).merge(SUBSCRIPTION_ID_META => subscription_id)
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
