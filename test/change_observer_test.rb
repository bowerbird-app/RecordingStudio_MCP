# frozen_string_literal: true

require "test_helper"

class ChangeObserverTest < Minitest::Test
  FakeEvent = Struct.new(:recording)

  def test_install_is_idempotent_and_forwards_after_record
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      RecordingStudio.configuration.hooks.clear(:after_record)
      RecordingStudioMcp::ChangeObserver.instance_variable_set(:@installed, nil)
      RecordingStudioMcp::ChangeObserver.install!
      RecordingStudioMcp::ChangeObserver.install!

      notified = []
      RecordingStudioMcp::Notifier.stub(:recording_saved, ->(event) { notified << event }) do
        event = FakeEvent.new(Object.new)
        RecordingStudioMcp::ChangeObserver.call(event)
        RecordingStudio.configuration.hooks.run(:after_record, event)
      end

      assert_equal 2, notified.length
    end
  end

  def test_after_record_waits_for_commit_when_a_transaction_is_open
    skip "ActiveRecord is missing" unless defined?(ActiveRecord::Base)
    ensure_active_record_connection!

    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      notified = []
      RecordingStudioMcp::Notifier.stub(:recording_saved, ->(event) { notified << event }) do
        event = FakeEvent.new(Object.new)
        ActiveRecord::Base.transaction do
          RecordingStudioMcp::ChangeObserver.call(event)
          assert_empty notified
        end
      end

      assert_equal 1, notified.length
    end
  end

  private

  # Gem suite has no Rails database.yml. CI sets DATABASE_URL; establish so
  # connected? is true after checkout (lazy pools skip this test otherwise).
  def ensure_active_record_connection!
    return if ActiveRecord::Base.connected?

    url = ENV["DATABASE_URL"].to_s.strip
    skip "DATABASE_URL is not set" if url.empty?

    ActiveRecord::Base.establish_connection(url)
    ActiveRecord::Base.connection.verify!
  end
end
