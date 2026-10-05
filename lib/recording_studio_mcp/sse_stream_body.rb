# frozen_string_literal: true

module RecordingStudioMcp
  class SseStreamBody
    def initialize(on_run:, on_disconnect: nil, on_abort: nil)
      @on_run = on_run
      @on_disconnect = on_disconnect
      @on_abort = on_abort
      @closed = false
      @started = false
      @mutex = Mutex.new
    end

    def each
      return if closed?

      @mutex.synchronize { @started = true }
      writer = SseWriter.new(
        ->(chunk) do
          raise IOError, "client disconnected" if closed?

          yield chunk
        end,
        on_disconnect: -> do
          close
          @on_disconnect&.call
        end
      )
      @on_run.call(writer)
    ensure
      writer&.close
    end

    def close
      abort = false
      @mutex.synchronize do
        return if @closed

        @closed = true
        abort = !@started
      end
      @on_abort&.call if abort
    end

    def closed?
      @mutex.synchronize { @closed }
    end
  end
end
