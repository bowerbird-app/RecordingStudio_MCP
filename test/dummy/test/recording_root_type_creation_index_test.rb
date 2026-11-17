# frozen_string_literal: true

require "test_helper"

class RecordingRootTypeCreationIndexTest < ActiveSupport::TestCase
  test "root type creation index orders created_at and id newest first with no where" do
    index = RecordingStudio::Recording.connection.indexes(:recording_studio_recordings).find do |candidate|
      candidate.name == "index_rs_recordings_on_root_type_created_at_id"
    end

    assert index
    assert_equal %w[root_recording_id recordable_type created_at id], Array(index.columns)
    assert_equal({ "created_at" => :desc, "id" => :desc }, index.orders)
    assert_nil index.where
    refute index.unique
  end
end
