# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "net/http"

class EventRpcTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type)
  FakeClient = Struct.new(:id)
  FakeGrant = Struct.new(:api_client, :accessible_recordings, :access_recording)
  Row = Struct.new(
    :id, :owner_principal_id, :access_recording_id, :event_name, :arguments, :callback_url, :callback_secret,
    :status, :expires_at, :last_error, :failure_count, keyword_init: true
  ) do
    def refresh!(secret:, expires_at:, access_recording_id: nil)
      self.callback_secret = secret
      self.expires_at = expires_at
      self.status = "active"
      self.last_error = nil
      self.access_recording_id = access_recording_id if access_recording_id
    end

    def deactivate!(message:)
      self.status = "inactive"
      self.last_error = message
    end
  end

  class MemoryStore
    attr_reader :rows

    def initialize
      @rows = []
    end

    def table_available?
      true
    end

    def find_by(id:)
      @rows.find { |row| row.id == id }
    end

    def where(**attrs)
      matched = @rows.select { |row| attrs.all? { |key, value| row.public_send(key) == value } }
      Object.new.tap { |relation| relation.define_singleton_method(:count) { matched.size } }
    end

    def create!(**attrs)
      row = Row.new(**attrs)
      @rows << row
      row
    end
  end

  def setup
    @store = MemoryStore.new
    @recording = FakeRecording.new("rec-1", "Page")
    @grant = FakeGrant.new(
      FakeClient.new("client-1"),
      Object.new.tap do |scope|
        recording = @recording
        scope.define_singleton_method(:find_by) { |id:| recording if recording.id.to_s == id.to_s }
      end
    )
    @secret = "whsec_#{Base64.strict_encode64('a' * 32)}"
    @url = "https://receiver.example.test/mcp_event_receiver"
  end

  def test_every_subscribe_rejection
    listed = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "events/list" },
      access_grant: @grant
    )
    assert_equal(-32_601, listed.body.dig(:error, :code))

    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "events/subscribe", "params" => subscribe_params },
      access_grant: @grant
    )
    assert_equal(-32_601, result.body.dig(:error, :code))

    with_events do
      assert_invalid("unknown event", subscribe_params.merge("name" => "nope.event"))
      assert_invalid("missing recording_id", subscribe_params.merge("arguments" => {}))
      assert_invalid(
        "unexpected argument",
        subscribe_params.merge("arguments" => { "recording_id" => "rec-1", "extra" => "1" })
      )
      assert_invalid("invalid recording_id", subscribe_params.merge("arguments" => { "recording_id" => 12 }))
      assert_invalid("not authorized", subscribe_params.merge("arguments" => { "recording_id" => "hidden" }))
      assert_invalid("invalid signing secret", subscribe_params.merge("delivery" => delivery.merge("secret" => "nope")))
      assert_invalid("delivery must be webhook", subscribe_params.merge("delivery" => delivery.merge("mode" => "sse")))
      http_url = subscribe_params.merge("delivery" => delivery.merge("url" => "http://receiver.example.test/hook"))
      error = call_subscribe(http_url)
      assert_equal(-32_015, error.body.dig(:error, :code))
      assert_equal "invalid_url", error.body.dig(:error, :data, :reason)

      loopback = subscribe_params.merge("delivery" => delivery.merge("url" => "https://localhost/hook"))
      error = call_subscribe(loopback)
      assert_equal "private_address", error.body.dig(:error, :data, :reason)

      RecordingStudioMcp.configuration.event_subscriptions_per_principal = 0
      assert_invalid("subscription limit reached", subscribe_params)
    end
  end

  def test_deterministic_id_and_refresh
    with_events do
      RecordingStudioMcp::CallbackVerifier.stub(:verify!, true) do
        first = call_subscribe(subscribe_params)
        second = call_subscribe(subscribe_params)

        assert_equal first.body.dig(:result, :id), second.body.dig(:result, :id)
        assert_equal 1, @store.rows.size
        assert second.body.dig(:result, :refreshBefore).present?
        assert_nil second.body.dig(:result, :cursor)
        assert_equal false, second.body.dig(:result, :truncated)
      end
    end
  end

  def test_ttl_ms_caps_granted_expiry
    with_events do
      RecordingStudioMcp::CallbackVerifier.stub(:verify!, true) do
        result = call_subscribe(subscribe_params.merge("ttlMs" => 120_000))
        refresh = Time.iso8601(result.body.dig(:result, :refreshBefore))
        assert_operator refresh, :<=, 3.minutes.from_now
        assert_operator refresh, :>=, 90.seconds.from_now
      end
    end
  end

  def test_unsubscribe_is_owner_only
    with_events do
      RecordingStudioMcp::CallbackVerifier.stub(:verify!, true) do
        created = call_subscribe(subscribe_params)
        id = created.body.dig(:result, :id)
        outsider = FakeGrant.new(FakeClient.new("client-2"), @grant.accessible_recordings)
        with_store do
          RecordingStudioMcp::EventRpc.unsubscribe(
            params: subscribe_params,
            access_grant: outsider
          )
        end
        assert_equal "active", @store.find_by(id: id).status

        with_store do
          RecordingStudioMcp::EventRpc.unsubscribe(params: subscribe_params, access_grant: @grant)
        end
        assert_equal "inactive", @store.find_by(id: id).status
      end
    end
  end

  def test_callback_verification_failure_is_callback_endpoint_error
    with_events do
      RecordingStudioMcp::CallbackVerifier.stub(
        :verify!,
        ->(*) { raise RecordingStudioMcp::CallbackUrl::Error.new(:challenge_failed, "nope") }
      ) do
        error = call_subscribe(subscribe_params)
        assert_equal(-32_015, error.body.dig(:error, :code))
        assert_equal "challenge_failed", error.body.dig(:error, :data, :reason)
        assert_empty @store.rows
      end
    end
  end

  def test_list_returns_recording_updated_schema
    with_events do
      listed = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 9, "method" => "events/list" },
        access_grant: @grant
      )
      event = listed.body.dig(:result, :events).first
      assert_equal "recording.updated", event[:name]
      assert_equal ["webhook"], event[:delivery]
      assert_includes event[:inputSchema]["required"], "recording_id"
    end
  end

  def test_discover_advertises_events_only_when_enabled
    grant = Struct.new(:api_client).new(nil)
    hidden = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 10, "method" => "server/discover" },
      access_grant: grant
    )
    refute hidden.body.dig(:result, :capabilities).key?(:events)

    with_events do
      shown = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 11, "method" => "server/discover" },
        access_grant: grant
      )
      assert_equal({}, shown.body.dig(:result, :capabilities, :events))
    end
  end

  private

  def with_events
    with_isolated_mcp_configuration do
      RecordingStudioMcp.configuration.events_enabled = true
      RecordingStudioMcp.register_event("recording updated")
      yield
    end
  end

  def subscribe_params
    {
      "name" => "recording.updated",
      "arguments" => { "recording_id" => "rec-1" },
      "delivery" => delivery,
      "cursor" => nil
    }
  end

  def delivery
    { "mode" => "webhook", "url" => @url, "secret" => @secret }
  end

  def call_subscribe(params)
    with_store do
      RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 2, "method" => "events/subscribe", "params" => params },
        access_grant: @grant
      )
    end
  end

  def with_store(&)
    RecordingStudioMcp::EventRpc.stub(:records, @store, &)
  end

  def assert_invalid(message, params)
    result = call_subscribe(params)
    assert_equal(-32_602, result.body.dig(:error, :code), result.body.inspect)
    assert_equal message, result.body.dig(:error, :message)
  end
end
