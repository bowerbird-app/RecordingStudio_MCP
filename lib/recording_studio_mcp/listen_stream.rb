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
        writer.write_comment if keepalive?
        connection.wait(timeout: KEEPALIVE_SECONDS)
      end
    end

    def keepalive?
      KEEPALIVE_SECONDS.positive?
    end
  end
end
