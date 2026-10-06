# frozen_string_literal: true

require "test_helper"

class WebhookDispatchTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type)
  FakeSubscription = Struct.new(:id, :failure_message, keyword_init: true) do
    def matches_recording?(recording)
      recording.id.to_s == "rec-1"
    end

    def record_failure!(message:, inactive: false)
      self.failure_message = message
    end
  end

  def test_skips_when_events_disabled
    called = false
    RecordingStudioMcp::WebhookDispatch.stub(:ready?, -> { called = true }) do
      RecordingStudioMcp::WebhookDispatch.enqueue(event_name: "recording updated", recording_id: "rec-1")
    end
    refute called
  end

  def test_enqueues_a_signed_delivery_job
    with_isolated_mcp_configuration do
      RecordingStudioMcp.configuration.events_enabled = true
      RecordingStudioMcp.register_event("recording updated")
      recording = FakeRecording.new("rec-1", "Page")
      subscription = FakeSubscription.new(id: "sub_1")
      jobs = []

      RecordingStudioMcp::WebhookDispatch.stub(:ready?, true) do
        RecordingStudioMcp::WebhookDispatch.stub(:subscriptions_for, [subscription]) do
          RecordingStudioMcp::WebhookDispatch.stub(:still_accessible?, true) do
            RecordingStudioMcp::WebhookDispatch.stub(:queue_delivery, ->(**args) { jobs << args }) do
              RecordingStudioMcp::WebhookDispatch.enqueue(
                event_name: "recording updated",
                recording_id: "rec-1",
                recording: recording
              )
            end
          end
        end
      end

      assert_equal 1, jobs.size
      assert_equal "sub_1", jobs.first[:subscription_id]
      refute_nil jobs.first[:event_id]
      payload = JSON.parse(jobs.first[:body])
      assert_equal "recording.updated", payload["name"]
      assert_equal "rec-1", payload.dig("data", "recording_id")
    end
  end

  def test_rebuilds_access_grant_from_oauth_client_and_stored_access_recording
    oauth_client = Object.new
    access_recording = Object.new
    access_recording.define_singleton_method(:root_recording) { :root }
    subscription = Struct.new(:owner_principal_id, :access_recording_id).new("oauth-1", "acc-1")

    RecordingStudioOauth::OauthClient.stub(:find_by, ->(id:) { oauth_client if id == "oauth-1" }) do
      RecordingStudio::Recording.stub(:find_by, ->(id:) { access_recording if id == "acc-1" }) do
        grant = RecordingStudioMcp::WebhookDispatch.send(:access_grant_for, subscription)

        assert_equal oauth_client, grant.api_client
        assert_equal access_recording, grant.access_recording
        assert_equal :root, grant.root_recording
      end
    end
  end
end
