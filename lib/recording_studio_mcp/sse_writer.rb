# frozen_string_literal: true

require "json"

module RecordingStudioMcp
  class SseWriter
    DISCONNECT_ERRORS = [
      IOError,
      Errno::EPIPE,
      Errno::ECONNRESET,
      Errno::ECONNABORTED
    ].freeze

    def initialize(output = nil, on_disconnect: nil, &block)
      @output = output || block
      raise ArgumentError, "SSE writer needs an output" if @output.nil?

      @on_disconnect = on_disconnect
      @mutex = Mutex.new
      @closed = false
      @disconnected = false
    end

    def write_json(payload)
      emit(sse_event(payload))
    end

    def close
      should_close = false
      @mutex.synchronize do
        return if @closed

        @closed = true
        should_close = true
      end
      close_output if should_close
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    def disconnected?
      @mutex.synchronize { @disconnected }
    end

    private

    def sse_event(payload)
      json = JSON.generate(payload)
      "event: message\ndata: #{json}\n\n"
    end

    def emit(chunk)
      notify_disconnect = write_or_disconnect(chunk)
      return unless notify_disconnect

      @on_disconnect&.call
      close_output
    end

    def write_or_disconnect(chunk)
      @mutex.synchronize do
        return false if @closed

        write_chunk(chunk)
        false
      rescue *DISCONNECT_ERRORS
        first = !@disconnected
        @disconnected = true
        @closed = true
        first
      end
    end

    def write_chunk(chunk)
      if @output.respond_to?(:write)
        @output.write(chunk)
        @output.flush if @output.respond_to?(:flush)
      else
        @output.call(chunk)
      end
    end

    def close_output
      return unless @output.respond_to?(:close)
      return if @output.equal?($stdout) || @output.equal?($stderr)

      @output.close
    rescue *DISCONNECT_ERRORS
      @mutex.synchronize { @disconnected = true }
    end
  end
end
