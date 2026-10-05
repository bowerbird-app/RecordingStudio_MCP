# frozen_string_literal: true

require "test_helper"

class SseWriterTest < Minitest::Test
  FakeIO = Struct.new(:chunks, :flushes, :closed, keyword_init: true) do
    def initialize(chunks: [], flushes: 0, closed: false, fail_after: nil)
      super(chunks: chunks, flushes: flushes, closed: closed)
      @fail_after = fail_after
    end

    def write(chunk)
      raise IOError, "broken pipe" if @fail_after && chunks.length >= @fail_after

      chunks << chunk
    end

    def flush
      self.flushes += 1
    end

    def close
      self.closed = true
    end
  end

  def test_frames_json_as_sse_and_flushes_each_message
    io = FakeIO.new
    writer = RecordingStudioMcp::SseWriter.new(io)
    writer.write_json({ jsonrpc: "2.0", method: "notifications/progress", params: { progressToken: "t", progress: 1 } })
    writer.write_json({ jsonrpc: "2.0", id: 7, result: { ok: true } })
    writer.close

    assert_equal 2, io.chunks.length
    assert_equal 2, io.flushes
    assert_equal true, io.closed
    first = io.chunks.first
    assert_includes first, "event: message\n"
    assert_includes first, "data: "
    payload = JSON.parse(first.split("data: ", 2).last)
    refute payload.key?("id")
    assert_equal "notifications/progress", payload["method"]
    second = JSON.parse(io.chunks.last.split("data: ", 2).last)
    assert_equal 7, second["id"]
  end

  def test_comment_lines_are_keepalive_frames
    io = FakeIO.new
    writer = RecordingStudioMcp::SseWriter.new(io)
    writer.write_comment
    writer.close

    assert_equal ":\n\n", io.chunks.first
  end

  def test_writes_are_serialized_across_threads
    io = FakeIO.new
    writer = RecordingStudioMcp::SseWriter.new(io)
    threads = 10.times.map do |index|
      Thread.new { writer.write_json({ n: index }) }
    end
    threads.each(&:join)
    writer.close

    assert_equal 10, io.chunks.length
    io.chunks.each do |chunk|
      assert_match(/\Aevent: message\ndata: .+\n\n\z/m, chunk)
    end
  end

  def test_disconnect_closes_and_notifies_once
    io = FakeIO.new(fail_after: 0)
    notices = 0
    writer = RecordingStudioMcp::SseWriter.new(io, on_disconnect: -> { notices += 1 })
    writer.write_json({ n: 1 })
    writer.write_json({ n: 2 })
    writer.close

    assert_equal true, writer.disconnected?
    assert_equal true, writer.closed?
    assert_equal 1, notices
    assert_empty io.chunks
  end
end
