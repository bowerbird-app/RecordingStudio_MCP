# frozen_string_literal: true

require "test_helper"
require "base64"
require "net/http"

class WebhookDeliveryTest < Minitest::Test
  FakeSubscription = Struct.new(
    :id, :callback_url, :callback_secret, :status, :failure_count, :last_error, :last_delivered_at,
    keyword_init: true
  ) do
    def active?
      status == "active"
    end

    def mark_delivered!
      self.last_delivered_at = Time.now
      self.failure_count = 0
      self.last_error = nil
    end

    def record_failure!(message:, inactive: false)
      self.failure_count = failure_count.to_i + 1
      self.last_error = message
      self.status = "inactive" if inactive || failure_count >= 5
    end

    def deactivate!(message:)
      self.status = "inactive"
      self.last_error = message
    end

    def reload
      self
    end
  end

  def setup
    @subscription = FakeSubscription.new(
      id: "sub_1",
      callback_url: "https://receiver.example.test/hook",
      callback_secret: "whsec_#{Base64.strict_encode64('a' * 32)}",
      status: "active",
      failure_count: 0
    )
  end

  def test_deactivates_on_410
    gone = Net::HTTPGone.new("1.1", "410", "Gone")
    gone.define_singleton_method(:code) { "410" }

    RecordingStudioMcp::CallbackHttp.stub(:post, gone) do
      RecordingStudioMcp::WebhookDelivery.call(
        subscription: @subscription,
        body: "{}",
        event_id: "evt_1"
      )
    end

    assert_equal "inactive", @subscription.status
    assert_equal "410", @subscription.last_error
  end

  def test_repeated_failures_mark_inactive
    @subscription.failure_count = 4
    fail_response = Net::HTTPServerError.new("1.1", "500", "Err")
    fail_response.define_singleton_method(:code) { "500" }

    RecordingStudioMcp::CallbackHttp.stub(:post, fail_response) do
      RecordingStudioMcp::WebhookDelivery.call(
        subscription: @subscription,
        body: "{}",
        event_id: "evt_1"
      )
    end

    assert_equal "inactive", @subscription.status
  end

  def test_skips_payloads_over_256_kib
    posted = false
    RecordingStudioMcp::CallbackHttp.stub(:post, ->(*) { posted = true }) do
      RecordingStudioMcp::WebhookDelivery.call(
        subscription: @subscription,
        body: "x" * ((256 * 1024) + 1),
        event_id: "evt_1"
      )
    end

    refute posted
    assert_equal "payload exceeds 256 KiB", @subscription.last_error
    assert_equal "active", @subscription.status
  end

  def test_retryable_server_error_raises_transient_failure
    fail_response = Net::HTTPServerError.new("1.1", "500", "Err")
    fail_response.define_singleton_method(:code) { "500" }

    RecordingStudioMcp::CallbackHttp.stub(:post, fail_response) do
      assert_raises(RecordingStudioMcp::TransientWebhookFailure) do
        RecordingStudioMcp::WebhookDelivery.call(
          subscription: @subscription,
          body: "{}",
          event_id: "evt_1"
        )
      end
    end

    assert_equal "active", @subscription.status
    assert_equal 1, @subscription.failure_count
  end
end
