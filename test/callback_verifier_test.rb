# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "net/http"

class CallbackVerifierTest < Minitest::Test
  def setup
    RecordingStudioMcp::CallbackVerifier.reset_cache!
    @secret = "whsec_#{Base64.strict_encode64('v' * 32)}"
  end

  def teardown
    RecordingStudioMcp::CallbackVerifier.reset_cache!
  end

  def test_requires_echoed_challenge_then_caches
    calls = 0
    RecordingStudioMcp::CallbackHttp.stub(:post, lambda { |_url, body:, headers:|
      calls += 1
      payload = JSON.parse(body)
      ok = Net::HTTPOK.new("1.1", "200", "OK")
      ok.instance_variable_set(:@read, true)
      ok.define_singleton_method(:body) { { "challenge" => payload["challenge"] }.to_json }
      assert headers["webhook-id"].start_with?("msg_verification_")
      ok
    }) do
      RecordingStudioMcp::CallbackVerifier.verify!(
        principal_id: "client-1",
        url: "https://receiver.example.test/hook",
        secret: @secret,
        subscription_id: "sub_1"
      )
      RecordingStudioMcp::CallbackVerifier.verify!(
        principal_id: "client-1",
        url: "https://receiver.example.test/hook",
        secret: @secret,
        subscription_id: "sub_1"
      )
    end

    assert_equal 1, calls
  end

  def test_timeout_is_callback_error
    RecordingStudioMcp::CallbackHttp.stub(:post, ->(*) { raise Net::OpenTimeout }) do
      error = assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
        RecordingStudioMcp::CallbackVerifier.verify!(
          principal_id: "client-1",
          url: "https://receiver.example.test/hook",
          secret: @secret,
          subscription_id: "sub_1"
        )
      end
      assert_equal :timeout, error.reason
    end
  end
end
