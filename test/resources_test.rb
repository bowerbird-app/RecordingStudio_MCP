# frozen_string_literal: true

require "test_helper"

class ResourcesTest < Minitest::Test
  FakeGrant = Struct.new(:recordings) do
    def accessible_recordings
      recordings
    end
  end

  FakeRecording = Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)

  FakeScope = Struct.new(:rows) do
    def includes(*)
      self
    end

    def order(*)
      rows
    end

    def find_by(id:)
      rows.find { |row| row.id.to_s == id.to_s }
    end

    def exists?(id:)
      rows.any? { |row| row.id.to_s == id.to_s }
    end
  end

  def test_list_and_read_use_stable_recording_uris
    recording = FakeRecording.new(42, "Page", Struct.new(:title).new("Hello"), nil, 1)
    grant = FakeGrant.new(FakeScope.new([recording]))

    listed = RecordingStudioMcp::Resources.list(access_grant: grant)
    assert_equal "recording://42", listed.payload[:resources].first[:uri]
    assert_equal "Hello", listed.payload[:resources].first[:name]

    read = RecordingStudioMcp::Resources.read(access_grant: grant, uri: "recording://42")
    payload = JSON.parse(read.payload[:contents].first[:text])
    assert_equal 42, payload["id"]
    assert_equal "Page", payload["type"]
    assert_equal "Hello", payload["title"]
  end

  def test_read_hides_recordings_outside_the_grant
    grant = FakeGrant.new(FakeScope.new([]))
    answer = RecordingStudioMcp::Resources.read(access_grant: grant, uri: "recording://99")

    assert_instance_of RecordingStudioMcp::Resources::NotFound, answer
    refute RecordingStudioMcp::Resources.accessible?(grant, "recording://99")
  end

  def test_unknown_uris_are_invalid
    grant = FakeGrant.new(FakeScope.new([]))

    assert_instance_of RecordingStudioMcp::Resources::InvalidParams,
                       RecordingStudioMcp::Resources.read(access_grant: grant, uri: "file://nope")
    assert_instance_of RecordingStudioMcp::Resources::InvalidParams,
                       RecordingStudioMcp::Resources.list(access_grant: grant, cursor: "next")
  end
end
