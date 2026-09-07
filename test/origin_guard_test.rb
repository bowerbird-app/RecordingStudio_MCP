# frozen_string_literal: true

require "test_helper"

class OriginGuardTest < Minitest::Test
  def test_allows_requests_without_origin
    assert RecordingStudioMcp::OriginGuard.allowed?(
      nil,
      request_origin: "https://studio.example",
      allowed_origins: []
    )
  end

  def test_allows_same_origin_and_configured_origins
    assert RecordingStudioMcp::OriginGuard.allowed?(
      "https://studio.example",
      request_origin: "https://studio.example",
      allowed_origins: []
    )
    assert RecordingStudioMcp::OriginGuard.allowed?(
      "https://client.example",
      request_origin: "https://studio.example",
      allowed_origins: ["https://client.example"]
    )
  end

  def test_rejects_unlisted_origin
    refute RecordingStudioMcp::OriginGuard.allowed?(
      "https://attacker.example",
      request_origin: "https://studio.example",
      allowed_origins: ["https://client.example"]
    )
  end
end
