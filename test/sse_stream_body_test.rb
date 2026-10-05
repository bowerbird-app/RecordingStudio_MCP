# frozen_string_literal: true

require "test_helper"

class SseStreamBodyTest < Minitest::Test
  def test_each_yields_chunks_then_closes_the_writer
    yielded = []
    body = RecordingStudioMcp::SseStreamBody.new(
      on_run: lambda do |writer|
        writer.write_json({ n: 1 })
        writer.write_json({ n: 2 })
      end
    )

    body.each { |chunk| yielded << chunk }

    assert_equal 2, yielded.length
    assert yielded.all? { |chunk| chunk.start_with?("event: message\n") }
  end

  def test_close_before_each_runs_abort_and_skips_work
    ran = false
    aborted = false
    body = RecordingStudioMcp::SseStreamBody.new(
      on_abort: -> { aborted = true },
      on_run: ->(_writer) { ran = true }
    )
    body.close
    body.each { |_chunk| ran = true }

    assert aborted
    refute ran
  end

  def test_client_close_during_write_marks_disconnect
    disconnected = false
    body = RecordingStudioMcp::SseStreamBody.new(
      on_disconnect: -> { disconnected = true },
      on_run: lambda do |writer|
        writer.write_json({ n: 1 })
        writer.write_json({ n: 2 })
      end
    )

    chunks = 0
    begin
      body.each do |_chunk|
        chunks += 1
        body.close if chunks == 1
      end
    rescue IOError
      nil
    end

    assert disconnected
    assert_equal 1, chunks
  end
end
