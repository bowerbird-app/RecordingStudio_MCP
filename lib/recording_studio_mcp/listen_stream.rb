# frozen_string_literal: true

module RecordingStudioMcp
  class ListenStream
    KEEPALIVE_SECONDS = 15

    def initialize(connection:, request_context:, write_ack: false)
      @connection = connection
      @request_context = request_context
      @write_ack = write_ack
    end

    def perform(writer)
      attach(writer)
      writer.write_json(connection.acknowledged_payload) if write_ack
      park(writer)
    ensure
      complete_listen(writer)
      close_listen
    end

    def attach(writer)
      request_context.attach_sender(writer)
      connection.attach_sender(writer)
    end

    def close_listen
      request_context.complete!
      request_context.disconnect!
      connection.finish!
      Connections.drop(connection.id)
    end
    private :attach, :close_listen

    def disconnected?(writer)
      request_context.disconnected? || writer.disconnected? || connection.finished?
    end

    private

    attr_reader :connection, :request_context, :write_ack

    def park(writer)
      until disconnected?(writer)
        payload = connection.shift_pending(timeout: KEEPALIVE_SECONDS)
        if payload
          break unless connection.write_payload(writer, payload)
        elsif keepalive?
          writer.write_comment
        end
      end
    end

    def complete_listen(writer)
      return unless write_ack
      return if connection.subscription_id.nil?
      return if writer.disconnected? || writer.closed?

      # Server-ended listen writes SubscriptionsListenResult before close.
      writer.write_json(connection.listen_completion_payload)
    rescue *SseWriter::DISCONNECT_ERRORS
      nil
    end

    def keepalive?
      KEEPALIVE_SECONDS.positive?
    end
  end
end
