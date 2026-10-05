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

    def each(&block)
      return to_enum(:each) unless block
      return if closed?

      mark_started
      writer = writer_for(&block)
      @on_run.call(writer)
    ensure
      writer&.close if block
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

    private

    def mark_started
      @mutex.synchronize { @started = true }
    end

    def writer_for(&write)
      SseWriter.new(
        lambda { |chunk|
          raise IOError, "client disconnected" if closed?

          write.call(chunk)
        },
        on_disconnect: method(:handle_client_disconnect)
      )
    end

    def handle_client_disconnect
      close
      @on_disconnect&.call
    end
  end
end
