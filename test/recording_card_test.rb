# frozen_string_literal: true

require "test_helper"

class RecordingCardTest < Minitest::Test
  def test_untitled_resource_name_uses_the_public_type_and_recording_id
    recordable = UntitledFile.new
    recordable.id = 41
    card = RecordingStudioMcp::RecordingCard.new(
      recording_for(9, "RecordingStudioPresskits::Files", recordable),
      catalog: files_catalog
    )

    assert_equal "Files 9", card.name
    assert_equal "Files 9", card.list_entry[:name]
    assert_nil card.title
    assert_equal "Files", card.payload[:type]
    refute_includes card.name, recordable.class.name
    refute_includes card.name, "41"
  end

  def test_titled_resource_keeps_its_name
    recordable = TitledFile.new
    recordable.title = "Launch kit"
    card = RecordingStudioMcp::RecordingCard.new(
      recording_for(9, "RecordingStudioPresskits::Files", recordable),
      catalog: files_catalog
    )

    assert_equal "Launch kit", card.name
    assert_equal "Launch kit", card.title
  end

  class UntitledFile
    attr_accessor :id
  end

  class TitledFile
    attr_accessor :id, :title
  end

  def files_catalog
    names = { "RecordingStudioPresskits::Files" => "Files" }
    Object.new.tap do |catalog|
      catalog.define_singleton_method(:displayed_type_name) { |type| names.fetch(type.to_s, type.to_s) }
    end
  end

  def recording_for(id, type, recordable)
    Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)
          .new(id, type, recordable, nil, 1)
  end
end
