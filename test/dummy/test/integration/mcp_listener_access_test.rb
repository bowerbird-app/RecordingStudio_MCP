# frozen_string_literal: true

require "test_helper"
require "base64"
require "securerandom"

class McpListenerAccessTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    @owner = create_user
    @root_recording, @root_access = create_access_recording_for(user: @owner)
    Current.actor = @owner
    @folder = @root_recording.record(Folder, actor: @owner) { |folder| folder.name = "Notes" }
    @viewer = create_user
    granted = RecordingStudioAccessible.grant_access(
      recording: @folder,
      actor: @viewer,
      role: "view",
      manager_actor: @owner
    )
    raise granted.error unless granted.success?

    @subtree_access = granted.value
    @page = @folder.record(Page, actor: @owner, parent_recording: @folder) { |page| page.title = "Inside" }
    @outside = @root_recording.record(Page, actor: @owner) { |page| page.title = "Outside" }
    @root_client, = create_oauth_client(name: "Root listeners #{SecureRandom.hex(4)}")
    @subtree_client, = create_oauth_client(name: "Subtree listeners #{SecureRandom.hex(4)}")
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "listeners on one grant share one access check and a subtree grant stays separate" do
    root_listeners = open_listeners(@root_client, @root_access, 8)
    subtree_listeners = open_listeners(@subtree_client, @subtree_access, 8)
    prime_grants(root_listeners + subtree_listeners)

    queries = count_queries { deliver(@page) }

    assert_operator queries, :<, root_listeners.size + subtree_listeners.size
    assert_equal 8, pending_count(root_listeners)
    assert_equal 8, pending_count(subtree_listeners)

    drain(root_listeners + subtree_listeners)
    outside_queries = count_queries { deliver(@outside) }

    assert_operator outside_queries, :<, root_listeners.size + subtree_listeners.size
    assert_equal 8, pending_count(root_listeners)
    assert_equal 0, pending_count(subtree_listeners)
  end

  test "an sse listener whose access was removed gets nothing" do
    root_listeners = open_listeners(@root_client, @root_access, 1)
    subtree_listeners = open_listeners(@subtree_client, @subtree_access, 1)
    revoke_subtree_grant!

    deliver(@page)

    assert_equal 1, pending_count(root_listeners)
    assert_equal 0, pending_count(subtree_listeners)
  end

  test "a trashed recording is not posted after the job was enqueued" do
    subscription = create_subscription(@subtree_client, @subtree_access, @page)
    job = capture_delivery
    @page.update_column(:trashed_at, Time.current)

    refute_posted { perform_captured(job) }
    assert subscription.reload.active?
  end

  test "a revoked grant gets no webhook after the job was enqueued" do
    create_subscription(@subtree_client, @subtree_access, @page)
    job = capture_delivery
    revoke_subtree_grant!

    refute_posted { perform_captured(job) }
  end

  test "a trashed grant gets no webhook after the job was enqueued" do
    create_subscription(@subtree_client, @subtree_access, @page)
    job = capture_delivery
    @subtree_access.update_column(:trashed_at, Time.current)

    refute_posted { perform_captured(job) }
  end

  test "webhook enqueue does not check access once per subscription" do
    8.times { create_subscription(@root_client, @root_access, @page) }

    queries = count_queries { enqueue_page }

    assert_operator queries, :<, 8
  end

  private

  def prime_grants(connections)
    connections.each { |connection| connection.access_grant.accessible_recordings }
  end

  def open_listeners(client, access_recording, count)
    uris = [@page, @outside].map { |recording| "recording://#{recording.id}" }
    count.times.map do
      connection = RecordingStudioMcp::Connections.open(
        protocol_version: "2025-06-18",
        access_grant: build_grant(client, access_recording)
      )
      uris.each { |uri| connection.subscribe(uri) }
      connection
    end
  end

  def build_grant(client, access_recording)
    RecordingStudioApi::AccessGrant.new(
      api_client: client,
      credential: nil,
      access_recording: access_recording,
      root_recording: access_recording.root_recording
    )
  end

  def deliver(recording)
    RecordingStudioMcp::Notifier.deliver_local(
      event_name: "recording updated",
      recording_id: recording.id,
      recording: recording
    )
  end

  def create_subscription(client, access_recording, recording)
    RecordingStudioMcp::EventSubscription.create!(
      id: "sub_#{SecureRandom.hex(12)}",
      owner_principal_id: client.id.to_s,
      access_recording_id: access_recording.id,
      event_name: "recording.updated",
      arguments: { "recording_id" => recording.id.to_s },
      callback_url: "https://receiver.example.test/listener",
      callback_secret: "whsec_#{Base64.strict_encode64(SecureRandom.bytes(32))}",
      status: "active",
      expires_at: 1.day.from_now
    )
  end

  def enqueue_page
    RecordingStudioMcp::WebhookDispatch.enqueue(
      event_name: "recording updated",
      recording_id: @page.id,
      recording: @page
    )
  end

  def capture_delivery
    enqueue_page
    ActiveJob::Base.queue_adapter.enqueued_jobs.last
  end

  def perform_captured(job)
    args = job.fetch(:args).first
    kwargs = args.symbolize_keys.except(:_aj_ruby2_keywords)
    RecordingStudioMcp::DeliverEventWebhookJob.perform_now(**kwargs)
  end

  def revoke_subtree_grant!
    result = RecordingStudioAccessible.revoke_access(
      recording: @folder,
      access_recording: @subtree_access,
      manager_actor: @owner
    )
    raise result.error unless result.success?
  end

  def pending_count(connections)
    connections.count(&:pending?)
  end

  def drain(connections)
    connections.each { |connection| connection.shift_pending(timeout: 0) while connection.pending? }
  end

  def count_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      name = payload[:name].to_s
      next if name == "SCHEMA" || name == "CACHE"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries << name
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    end
    queries.size
  end

  def refute_posted
    original = RecordingStudioMcp::CallbackHttp.method(:post)
    posted = false
    RecordingStudioMcp::CallbackHttp.define_singleton_method(:post) do |_url, body:, headers:|
      posted = true
      [body, headers]
    end
    yield
    refute posted
  ensure
    RecordingStudioMcp::CallbackHttp.define_singleton_method(:post, original)
  end
end
