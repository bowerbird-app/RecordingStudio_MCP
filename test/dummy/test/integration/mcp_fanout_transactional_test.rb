# frozen_string_literal: true

require "test_helper"

# Host `bin/rails test` uses transactional fixtures. The bus must not auto-LISTEN
# in test (see PostgresBus.start_allowed?), or Fanout skips local delivery while
# NOTIFY sits in a never-committed transaction — 0 deliveries. With LISTEN off,
# local delivery runs once.
class McpFanoutTransactionalTest < ActiveSupport::TestCase
  include OauthDummyHelpers

  setup do
    ENV.delete(RecordingStudioMcp::PostgresBus::START_ENV)
    ENV.delete(RecordingStudioMcp::PostgresBus::IN_TEST_ENV)
    @user = create_user
    Current.actor = @user
    @root_recording, = create_access_recording_for(user: @user)
    @page_recording = @root_recording.record(Page) { |page| page.title = "Fixture page" }
  end

  teardown do
    RecordingStudioMcp::PostgresBus.stop!
    Current.actor = nil if defined?(Current)
  end

  test "revise delivers exactly once under transactional fixtures" do
    refute RecordingStudioMcp::PostgresBus.listening?,
           "PostgresBus must not auto-start in Rails.env.test?"

    uri = "recording://#{@page_recording.id}"
    grant = Object.new
    page_id = @page_recording.id
    grant.define_singleton_method(:accessible_recordings) do
      RecordingStudio::Recording.where(id: page_id)
    end
    connection = RecordingStudioMcp::Connections.open(
      protocol_version: "2025-06-18",
      access_grant: grant
    )
    connection.subscribe(uri)
    drain_pending!(connection)

    @root_recording.revise(@page_recording) { |page| page.title = "Fixture changed" }

    uris = []
    while (payload = connection.shift_pending(timeout: 0))
      uris << payload.dig(:params, :uri)
    end

    assert_equal [uri], uris
  end

  private

  def drain_pending!(connection)
    loop do
      break if connection.shift_pending(timeout: 0).nil?
    end
  end
end
