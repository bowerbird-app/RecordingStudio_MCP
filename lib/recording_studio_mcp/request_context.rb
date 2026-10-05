# frozen_string_literal: true

module RecordingStudioMcp
  class RequestContext
    PROTOCOL_WITH_PROGRESS_MESSAGE = "2025-06-18"

    attr_reader :request_id, :protocol_version, :access_grant, :progress_token

    def initialize(request_id:, protocol_version:, access_grant:, progress_token: nil, sender: nil)
      @request_id = request_id
      @protocol_version = protocol_version
      @access_grant = access_grant
      @progress_token = progress_token
      @sender = sender
      @mutex = Mutex.new
      @disconnected = false
      @completed = false
      @last_progress = nil
    end

    def attach_sender(sender)
      @sender = sender
    end

    def progress_reporter
      return unless @progress_token
      return unless @sender

      self
    end

    def cancelled?
      disconnected?
    end

    def progress(current:, total: nil, message: nil)
      payload = progress_payload(current: current, total: total, message: message)
      return if payload.nil? || @sender.nil?

      @sender.write_json(payload)
    end

    def disconnected?
      @mutex.synchronize { @disconnected } || sender_disconnected?
    end

    def completed?
      @mutex.synchronize { @completed }
    end

    def disconnect!
      @mutex.synchronize { @disconnected = true }
    end

    def complete!
      @mutex.synchronize { @completed = true }
    end

    private

    def sender_disconnected?
      @sender.respond_to?(:disconnected?) && @sender.disconnected?
    end

    def progress_payload(current:, total:, message:)
      @mutex.synchronize do
        return if @disconnected || @completed
        return if @progress_token.nil?
        return unless valid_progress?(current, total)

        params = { progressToken: @progress_token, progress: current }
        params[:total] = total unless total.nil?
        params[:message] = message if include_message?(message)
        @last_progress = current
        { jsonrpc: Protocol::JSONRPC_VERSION, method: "notifications/progress", params: params }
      end
    end

    def valid_progress?(current, total)
      return false unless current.is_a?(Numeric)
      return false if @last_progress && current <= @last_progress
      return true if total.nil?
      return false unless total.is_a?(Numeric)

      total >= current
    end

    def include_message?(message)
      protocol_version == PROTOCOL_WITH_PROGRESS_MESSAGE && message.is_a?(String)
    end
  end
end
