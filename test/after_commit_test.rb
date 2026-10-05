# frozen_string_literal: true

require "test_helper"

class AfterCommitTest < Minitest::Test
  def test_runs_immediately_without_a_transaction
    ran = []
    RecordingStudioMcp::AfterCommit.run { ran << :now }

    assert_equal [:now], ran
  end

  def test_requires_a_block
    assert_raises(ArgumentError) { RecordingStudioMcp::AfterCommit.run }
  end

  def test_schedules_on_an_open_transaction
    ran = []
    committed = nil
    transaction = Object.new
    transaction.define_singleton_method(:open?) { true }
    transaction.define_singleton_method(:after_commit) { |&block| committed = block }

    ActiveRecord::Base.stub(:connected?, true) do
      ActiveRecord::Base.stub(:current_transaction, transaction) do
        RecordingStudioMcp::AfterCommit.run { ran << :later }
      end
    end

    assert_empty ran
    committed.call
    assert_equal [:later], ran
  end

  def test_open_transaction_rescues_connection_errors
    ActiveRecord::Base.stub(:connected?, -> { raise "no db" }) do
      ran = []
      RecordingStudioMcp::AfterCommit.run { ran << :now }
      assert_equal [:now], ran
    end
  end
end
