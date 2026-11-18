# frozen_string_literal: true

require "test_helper"

class NotifierTest < Minitest::Test
  FakeGrant = Struct.new(:allowed_ids) do
    def accessible_recordings
      ids = allowed_ids
      Object.new.tap do |scope|
        scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
        scope.define_singleton_method(:find_by) { |id:| ids.include?(id) ? Object.new : nil }
      end
    end
  end

  FakeRecording = Struct.new(:id, :recordable_type, :published)
  FakeEvent = Struct.new(:recording)

  def test_registered_event_enqueues_only_for_subscribed_connections
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      watching = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      ignored = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      watching.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      payload = watching.shift_pending(timeout: 0)
      assert_equal "notifications/resources/updated", payload[:method]
      assert_equal "recording://7", payload.dig(:params, :uri)
      assert_nil ignored.shift_pending(timeout: 0)
    end
  end

  def test_save_returns_while_a_subscriber_queue_is_not_drained
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :<, 0.2
      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_full_queue_drops_the_slow_subscriber
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Connection::QUEUE_LIMIT.times do
        connection.try_enqueue_updated("recording://7")
      end
      assert connection.pending?
      connection.try_enqueue_updated("recording://7")
      assert connection.finished?
    end
  end

  def test_types_and_if_filters_skip_notify
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated") do |event|
        event.on :recording_updated
        event.types "Page"
        event.if { |recording| recording.published == true }
      end
      grant = FakeGrant.new([7, 8, 9])
      watching = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      watching.subscribe("recording://7")
      watching.subscribe("recording://8")
      watching.subscribe("recording://9")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", false)))
      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(8, "Folder", true)))
      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(9, "Page", true)))

      uris = []
      while (payload = watching.shift_pending(timeout: 0))
        uris << payload.dig(:params, :uri)
      end
      assert_equal ["recording://9"], uris
    end
  end

  def test_custom_notify_enqueues_and_unregistered_raises
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("comment added")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp.notify("comment added", recording: FakeRecording.new(7, "Page", true))
      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)

      assert_raises(ArgumentError) do
        RecordingStudioMcp.notify("never registered", recording: FakeRecording.new(7, "Page", true))
      end
      assert_raises(ArgumentError) do
        RecordingStudioMcp.notify("comment added", recording: nil)
      end
    end
  end

  def test_unregistered_events_never_notify
    with_isolated_mcp_configuration do
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_nil connection.shift_pending(timeout: 0)
    end
  end

  def test_deliver_local_loads_a_recording_by_id
    skip unless defined?(RecordingStudio::Recording)

    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")
      found = FakeRecording.new(7, "Page", true)
      RecordingStudio::Recording.stub(:find_by, found) do
        RecordingStudioMcp::Notifier.deliver_local(event_name: "recording updated", recording_id: 7)
      end

      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_event_without_a_recording_is_ignored
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      event = Object.new
      event.define_singleton_method(:recording) { nil }
      event.define_singleton_method(:recording_id) { 7 }

      RecordingStudioMcp::Notifier.recording_saved(event)
    end
  end

  def test_a_broken_connection_is_dropped
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([7])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")
      connection.define_singleton_method(:try_enqueue_updated) { |_| raise "queue down" }

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert connection.finished?
    end
  end

  def test_listeners_on_the_same_grant_check_access_once
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      calls = 0
      connections = Array.new(3) do
        open_counted_listener(client_id: "client-1", access_id: "access-1", allowed: [7], calls: -> { calls += 1 })
      end
      open_counted_listener(client_id: "client-1", access_id: "access-2", allowed: [7], calls: -> { calls += 1 })

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 2, calls
      connections.each do |connection|
        assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)
      end
    end
  end

  def test_a_later_save_checks_access_again
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      calls = 0
      connection = open_counted_listener(
        client_id: "client-1",
        access_id: "access-1",
        allowed: [7],
        calls: -> { calls += 1 }
      )

      event = FakeEvent.new(FakeRecording.new(7, "Page", true))
      RecordingStudioMcp::Notifier.recording_saved(event)
      connection.shift_pending(timeout: 0)
      RecordingStudioMcp::Notifier.recording_saved(event)

      assert_equal 2, calls
      assert_equal "recording://7", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_a_below_view_role_does_not_reuse_an_allow
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      calls = 0
      view = open_counted_listener(
        client_id: "client-1",
        access_id: "access-1",
        allowed: [7],
        role: "view",
        calls: -> { calls += 1 }
      )
      blocked = open_counted_listener(
        client_id: "client-1",
        access_id: "access-1",
        allowed: [],
        role: "none",
        calls: -> { calls += 1 }
      )

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 2, calls
      assert_equal "recording://7", view.shift_pending(timeout: 0).dig(:params, :uri)
      assert_nil blocked.shift_pending(timeout: 0)
    end
  end

  def test_a_revoked_or_trashed_grant_does_not_reuse_an_allow
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      calls = 0
      live = open_counted_listener(
        client_id: "client-1",
        access_id: "access-1",
        allowed: [7],
        calls: -> { calls += 1 }
      )
      trashed = open_counted_listener(
        client_id: "client-1",
        access_id: "access-1",
        allowed: [],
        calls: -> { calls += 1 }
      ) { |_grant, access| access.trashed_at = Time.now }
      revoked = open_counted_listener(
        client_id: "client-1",
        access_id: "access-1",
        allowed: [],
        calls: -> { calls += 1 }
      ) { |_grant, access| access.define_singleton_method(:destroyed?) { true } }

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 3, calls
      assert_equal "recording://7", live.shift_pending(timeout: 0).dig(:params, :uri)
      assert_nil trashed.shift_pending(timeout: 0)
      assert_nil revoked.shift_pending(timeout: 0)
    end
  end

  def test_a_moved_parent_anchor_does_not_reuse_a_stale_deny
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      calls = 0
      counter = -> { calls += 1 }
      stale = open_grant_listener(
        access: grant_access_recording(parent_id: "folder-old"),
        allowed: [],
        calls: counter
      )
      fresh = open_grant_listener(
        access: grant_access_recording(parent_id: "folder-new"),
        allowed: [7],
        calls: counter
      )

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 2, calls
      assert_nil stale.shift_pending(timeout: 0)
      assert_equal "recording://7", fresh.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_an_unprimed_grant_does_not_reuse_a_primed_allow
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      access = grant_access_recording
      calls = 0
      counter = -> { calls += 1 }
      primed = open_grant_listener(access: access, allowed: [7], calls: counter)
      unprimed = open_grant_listener(access: access, allowed: [], calls: counter, prime: false)

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 2, calls
      assert_equal "recording://7", primed.shift_pending(timeout: 0).dig(:params, :uri)
      assert_nil unprimed.shift_pending(timeout: 0)
    end
  end

  def test_a_trashed_or_revoked_snapshot_is_not_reused
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      access = grant_access_recording
      calls = 0
      counter = -> { calls += 1 }
      live = open_grant_listener(access: access, allowed: [7], calls: counter)
      access.trashed_at = Time.current
      trashed = open_grant_listener(access: access, allowed: [7], calls: counter)
      revoked_access = grant_access_recording
      revoked_access.define_singleton_method(:revoked?) { true }
      revoked = open_grant_listener(access: revoked_access, allowed: [7], calls: counter)

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 1, calls
      assert_equal "recording://7", live.shift_pending(timeout: 0).dig(:params, :uri)
      assert_nil trashed.shift_pending(timeout: 0)
      assert_nil revoked.shift_pending(timeout: 0)
    end
  end

  def test_a_reassigned_actor_does_not_reuse_an_allow
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      access = grant_access_recording(actor: Struct.new(:id).new("user-1"))
      calls = 0
      counter = -> { calls += 1 }
      first = open_grant_listener(access: access, allowed: [7], calls: counter)
      access.recordable.actor = Struct.new(:id).new("user-2")
      second = open_grant_listener(access: access, allowed: [], calls: counter)

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_equal 2, calls
      assert_equal "recording://7", first.shift_pending(timeout: 0).dig(:params, :uri)
      assert_nil second.shift_pending(timeout: 0)
    end
  end

  def test_access_removed_before_delivery_does_not_notify
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      allowed = [7]
      removed = open_counted_listener(client_id: "client-1", access_id: "removed", allowed: allowed, calls: -> {})
      kept = open_counted_listener(client_id: "client-2", access_id: "kept", allowed: [7], calls: -> {})
      allowed.clear

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_nil removed.shift_pending(timeout: 0)
      assert_equal "recording://7", kept.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_lost_access_does_not_notify
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://7")

      RecordingStudioMcp::Notifier.recording_saved(FakeEvent.new(FakeRecording.new(7, "Page", true)))

      assert_nil connection.shift_pending(timeout: 0)
    end
  end

  private

  def grant_access_recording(parent_id: nil, actor: nil)
    recordable = Struct.new(:role, :actor).new("view", actor)
    Struct.new(:id, :trashed_at, :parent_recording_id, :recordable).new("access-1", nil, parent_id, recordable)
  end

  def open_grant_listener(access:, allowed:, calls:, prime: true)
    client = Struct.new(:id).new("client-1")
    root = Struct.new(:id).new("root-1")
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: client,
      credential: nil,
      access_recording: access,
      root_recording: root
    )
    grant.send(:capture_prime_snapshot) if prime
    grant.define_singleton_method(:accessible_recordings) do
      calls.call
      ids = allowed
      scope = Object.new
      scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
      scope
    end
    connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
    connection.subscribe("recording://7")
    connection
  end

  def open_counted_listener(client_id:, access_id:, allowed:, calls:, role: "view")
    client = Struct.new(:id).new(client_id)
    access_recording = Struct.new(:id, :trashed_at).new(access_id, nil)
    root = Struct.new(:id).new("root-1")
    grant = Struct.new(:api_client, :access_recording, :root_recording, :role).new(
      client, access_recording, root, role
    )
    yield grant, access_recording if block_given?
    grant.define_singleton_method(:accessible_recordings) do
      calls.call
      ids = allowed
      scope = Object.new
      scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
      scope
    end
    connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
    connection.subscribe("recording://7")
    connection
  end
end
