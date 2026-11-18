# frozen_string_literal: true

require "test_helper"

class WebhookDispatchTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type)
  FakeSubscription = Struct.new(:id, :failure_message, keyword_init: true) do
    def matches_recording?(recording)
      recording.id.to_s == "rec-1"
    end

    def record_failure!(message:, _inactive: false)
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
          RecordingStudioMcp::WebhookDispatch.stub(:queue_delivery, ->(**args) { jobs << args }) do
            RecordingStudioMcp::WebhookDispatch.enqueue(
              event_name: "recording updated",
              recording_id: "rec-1",
              recording: recording
            )
          end
        end
      end

      assert_equal 1, jobs.size
      assert_equal "sub_1", jobs.first[:subscription_id]
      assert_equal "rec-1", jobs.first[:recording_id]
      refute_nil jobs.first[:event_id]
      refute jobs.first.key?(:body)
    end
  end

  def test_body_is_built_from_ids_after_access_is_allowed
    subscription = FakeSubscription.new(id: "sub_1")
    subscription.define_singleton_method(:event_name) { "recording.updated" }

    payload = JSON.parse(
      RecordingStudioMcp::WebhookDispatch.body_for(
        subscription: subscription,
        recording_id: "rec-1",
        event_id: "evt_1"
      )
    )

    assert_equal "evt_1", payload["eventId"]
    assert_equal "recording.updated", payload["name"]
    assert_equal "rec-1", payload.dig("data", "recording_id")
    assert_equal "recording://rec-1", payload.dig("data", "uri")
  end

  def test_records_failure_when_payload_exceeds_256_kib
    subscription = FakeSubscription.new(id: "sub_1")
    subscription.define_singleton_method(:event_name) { "recording.updated" }

    body = RecordingStudioMcp::WebhookDispatch.stub(:serialized_body, "x" * ((256 * 1024) + 1)) do
      RecordingStudioMcp::WebhookDispatch.body_for(
        subscription: subscription,
        recording_id: "rec-1",
        event_id: "evt_1"
      )
    end

    assert_nil body
    assert_equal "payload exceeds 256 KiB", subscription.failure_message
  end

  def test_enqueues_before_checking_access
    with_isolated_mcp_configuration do
      RecordingStudioMcp.configuration.events_enabled = true
      RecordingStudioMcp.register_event("recording updated")
      recording = FakeRecording.new("rec-1", "Page")
      subscription = FakeSubscription.new(id: "sub_1")
      jobs = []
      checks = 0

      RecordingStudioMcp::WebhookDispatch.stub(:ready?, true) do
        RecordingStudioMcp::WebhookDispatch.stub(:subscriptions_for, [subscription]) do
          RecordingStudioMcp::WebhookDispatch.stub(:still_accessible?, lambda { |*|
            checks += 1
            false
          }) do
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
      assert_equal 0, checks
    end
  end

  def test_delivery_is_refused_when_access_is_gone
    subscription = FakeSubscription.new(id: "sub_1")
    subscription.define_singleton_method(:active?) { true }
    RecordingStudioMcp::WebhookDispatch.stub(:still_accessible?, false) do
      refute RecordingStudioMcp::WebhookDispatch.delivery_allowed?(subscription: subscription, recording_id: "rec-1")
    end
  end

  def test_delivery_is_refused_without_an_active_subscription
    inactive = FakeSubscription.new(id: "sub_1")
    inactive.define_singleton_method(:active?) { false }
    active = FakeSubscription.new(id: "sub_2")
    active.define_singleton_method(:active?) { true }

    refute RecordingStudioMcp::WebhookDispatch.delivery_allowed?(subscription: nil, recording_id: "rec-1")
    refute RecordingStudioMcp::WebhookDispatch.delivery_allowed?(subscription: inactive, recording_id: "rec-1")
    refute RecordingStudioMcp::WebhookDispatch.delivery_allowed?(subscription: active, recording_id: "")
  end

  def test_trashed_grant_is_refused_after_the_scope_check
    access_recording = Object.new
    access_recording.define_singleton_method(:root_recording) { :root }
    access_recording.define_singleton_method(:kept?) { false }
    subscription = Struct.new(:owner_principal_id, :access_recording_id).new("oauth-1", "acc-1")
    recording = FakeRecording.new("rec-1", "Page")
    scope_checked = false

    RecordingStudioMcp::WebhookDispatch.stub(:principal_for, Object.new) do
      RecordingStudioMcp::WebhookDispatch.stub(:access_recording_for, access_recording) do
        RecordingStudioMcp::Resources.stub(:uri_for, "recording://rec-1") do
          RecordingStudioMcp::Resources.stub(:accessible?, lambda { |_grant, _uri|
            scope_checked = true
            true
          }) do
            refute RecordingStudioMcp::WebhookDispatch.still_accessible?(subscription, recording)
          end
        end
      end
    end

    assert scope_checked
  end

  def test_still_accessible_is_false_without_a_grant
    subscription = Struct.new(:owner_principal_id, :access_recording_id).new("missing", nil)
    recording = FakeRecording.new("rec-1", "Page")

    refute RecordingStudioMcp::WebhookDispatch.still_accessible?(subscription, recording)
  end

  def test_enqueue_skips_when_find_recording_returns_nil
    with_isolated_mcp_configuration do
      RecordingStudioMcp.configuration.events_enabled = true
      RecordingStudioMcp.register_event("recording updated")
      jobs = []

      RecordingStudioMcp::WebhookDispatch.stub(:ready?, true) do
        RecordingStudioMcp::WebhookDispatch.stub(:queue_delivery, ->(**args) { jobs << args }) do
          RecordingStudioMcp::WebhookDispatch.enqueue(
            event_name: "recording updated",
            recording_id: "rec-1"
          )
        end
      end

      assert_empty jobs
    end
  end

  def test_still_accessible_is_false_when_access_recording_for_returns_nil
    subscription = Struct.new(:owner_principal_id, :access_recording_id).new("oauth-1", "acc-1")
    recording = FakeRecording.new("rec-1", "Page")

    RecordingStudioMcp::WebhookDispatch.stub(:principal_for, Object.new) do
      refute RecordingStudioMcp::WebhookDispatch.still_accessible?(subscription, recording)
    end
  end

  def test_still_accessible_is_false_when_access_recording_id_is_blank
    subscription = Struct.new(:owner_principal_id, :access_recording_id).new("oauth-1", nil)
    recording = FakeRecording.new("rec-1", "Page")

    RecordingStudioMcp::WebhookDispatch.stub(:principal_for, Object.new) do
      refute RecordingStudioMcp::WebhookDispatch.still_accessible?(subscription, recording)
    end
  end

  def test_rebuilds_access_grant_from_oauth_principal_and_stored_access_recording
    oauth_client = Object.new
    access_recording = Object.new
    access_recording.define_singleton_method(:root_recording) { :root }
    subscription = Struct.new(:owner_principal_id, :access_recording_id).new("oauth-1", "acc-1")
    recording = FakeRecording.new("rec-1", "Page")
    captured = nil

    RecordingStudioMcp::WebhookDispatch.stub(:principal_for, oauth_client) do
      RecordingStudioMcp::WebhookDispatch.stub(:access_recording_for, access_recording) do
        RecordingStudioMcp::Resources.stub(:uri_for, "recording://rec-1") do
          RecordingStudioMcp::Resources.stub(:accessible?, lambda { |grant, _uri|
            captured = grant
            true
          }) do
            assert RecordingStudioMcp::WebhookDispatch.still_accessible?(subscription, recording)
          end
        end
      end
    end

    assert_equal oauth_client, captured.api_client
    assert_equal access_recording, captured.access_recording
    assert_equal :root, captured.root_recording
  end
end
