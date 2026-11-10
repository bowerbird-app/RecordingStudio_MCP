# frozen_string_literal: true

require "test_helper"

class RedocVendorTest < Minitest::Test
  BANNED = %w[
    cdn.redocly.com
    cdn.redoc.ly
    unpkg.com
    jsdelivr
    otel.cloud.redocly.com
  ].freeze

  def test_vendored_bundle_has_no_cdn_or_telemetry_urls
    js = File.read(File.join(RecordingStudioMcp::Redoc::DIRECTORY, "redoc.standalone.js"))

    BANNED.each do |needle|
      refute_includes js, needle
    end
    assert_includes js, "disableTelemetry"
    assert_includes js, "logo-mini.svg"
  end

  def test_license_and_assets_are_present
    dir = RecordingStudioMcp::Redoc::DIRECTORY
    license = File.read(File.join(dir, "LICENSE"))

    assert_includes license, "MIT"
    assert File.file?(File.join(dir, "logo-mini.svg"))
    assert File.file?(File.join(dir, "logo-mini-full.svg"))
    path, type = RecordingStudioMcp::Redoc.file_for("redoc.js")
    assert File.file?(path)
    assert_equal "text/javascript", type
  end
end
