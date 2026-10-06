# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "net/http"

class WebhookSignatureTest < Minitest::Test
  def test_matches_the_standard_webhooks_reference_vector
    secret = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
    id = "msg_p5jXN8AQM9LWM0D4loKWxJek"
    timestamp = 1_614_265_330
    body = '{"test": 2432232314}'
    expected = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="

    assert_equal expected, RecordingStudioMcp::WebhookSignature.header(
      id: id,
      timestamp: timestamp,
      body: body,
      secret: secret
    )
    assert RecordingStudioMcp::WebhookSignature.valid?(
      id: id,
      timestamp: timestamp,
      body: body,
      secret: secret,
      header: expected
    )
  end
end

class WebhookSecretTest < Minitest::Test
  def test_accepts_whsec_base64_of_24_to_64_bytes
    raw = "a" * 24
    secret = "whsec_#{Base64.strict_encode64(raw)}"

    assert_equal raw, RecordingStudioMcp::WebhookSecret.parse(secret)
  end

  def test_rejects_missing_prefix_short_key_and_bad_base64
    assert_nil RecordingStudioMcp::WebhookSecret.parse(Base64.strict_encode64("a" * 24))
    assert_nil RecordingStudioMcp::WebhookSecret.parse("whsec_#{Base64.strict_encode64('short')}")
    assert_nil RecordingStudioMcp::WebhookSecret.parse("whsec_%%%")
    assert_nil RecordingStudioMcp::WebhookSecret.parse("whsec_#{Base64.strict_encode64('a' * 65)}")
  end
end

class CanonicalJsonTest < Minitest::Test
  def test_sorts_object_keys
    dumped = RecordingStudioMcp::CanonicalJson.dump("b" => 1, "a" => 2)

    assert_equal '{"a":2,"b":1}', dumped
  end
end

class CallbackUrlTest < Minitest::Test
  def test_rejects_http_loopback_and_link_local_hosts
    assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
      RecordingStudioMcp::CallbackUrl.parse!("http://example.com/hook")
    end
    error = assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
      RecordingStudioMcp::CallbackUrl.parse!("https://localhost/hook")
    end
    assert_equal :private_address, error.reason
  end

  def test_blocks_private_resolved_addresses
    Resolv.stub(:getaddresses, ["10.0.0.4"]) do
      error = assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
        RecordingStudioMcp::CallbackUrl.resolve!("https://receiver.example.test/hook")
      end
      assert_equal :private_address, error.reason
    end
  end

  def test_blocks_link_local_and_loopback_ips
    %w[127.0.0.1 169.254.1.1 ::1].each do |address|
      Resolv.stub(:getaddresses, [address]) do
        error = assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
          RecordingStudioMcp::CallbackUrl.resolve!("https://receiver.example.test/hook")
        end
        assert_equal :private_address, error.reason
      end
    end
  end

  def test_allowlist_hook_can_reject_a_public_host
    with_isolated_mcp_configuration do
      RecordingStudioMcp.configuration.event_callback_host_allowed = ->(host) { host == "ok.example" }
      error = assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
        RecordingStudioMcp::CallbackUrl.parse!("https://other.example/hook")
      end
      assert_equal :host_not_allowed, error.reason
    end
  end
end

class CallbackHttpTest < Minitest::Test
  def test_does_not_follow_redirects
    parsed = RecordingStudioMcp::CallbackUrl::Parsed.new(
      uri: URI.parse("https://receiver.example.test/hook"),
      addresses: ["1.1.1.1"]
    )
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    http = Object.new
    %i[ipaddr= hostname= use_ssl= verify_mode= open_timeout= read_timeout= write_timeout= max_retries=].each do |setter|
      http.define_singleton_method(setter) { |*| true }
    end
    http.define_singleton_method(:request) { |_req| redirect }

    RecordingStudioMcp::CallbackUrl.stub(:resolve!, parsed) do
      Net::HTTP.stub(:new, http) do
        error = assert_raises(RecordingStudioMcp::CallbackUrl::Error) do
          RecordingStudioMcp::CallbackHttp.post(
            "https://receiver.example.test/hook",
            body: "{}",
            headers: {}
          )
        end
        assert_equal :redirect, error.reason
      end
    end
  end
end
