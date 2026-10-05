# frozen_string_literal: true

module RecordingStudioMcp
  class StreamedCall
    def initialize(request_context:, access_grant:, raw_payload:, idempotency_key:)
      @request_context = request_context
      @access_grant = access_grant
      @raw_payload = raw_payload
      @idempotency_key = idempotency_key
    end

    def perform(writer)
      request_context.attach_sender(writer)
      result = dispatch
      write_final(writer, result)
      result
    ensure
      request_context.complete!
    end

    def dispatch
      Protocol.handle(
        raw_payload,
        access_grant: access_grant,
        idempotency_key: idempotency_key,
        request_context: request_context
      )
    end

    def disconnected?(writer)
      request_context.disconnected? || writer.disconnected?
    end

    private

    attr_reader :request_context, :access_grant, :raw_payload, :idempotency_key

    def write_final(writer, result)
      return unless result.body
      return if disconnected?(writer)

      writer.write_json(result.body)
    end
  end
end
