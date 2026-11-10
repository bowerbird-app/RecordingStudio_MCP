# frozen_string_literal: true

require "test_helper"
require "uri"

class RedocVendorTest < Minitest::Test
  ALLOWED_HOSTS = %w[
    chatgpt.com
    claude.ai
    commonmark.org
    en.wikipedia.org
    example.com
    github.com
    localhost
    localhost:4000
    localhost:4318
    react.dev
    www.w3.org
    reactrouter.com
    redocly.com
    yarnpkg.com
  ].freeze

  def test_vendored_bundle_https_hosts_are_allowlisted
    js = File.binread(File.join(RecordingStudioMcp::Redoc::DIRECTORY, "redoc.standalone.js"))
             .force_encoding(Encoding::UTF_8)
    hosts = remote_hosts(js)

    unexpected = hosts - ALLOWED_HOSTS
    assert_empty unexpected, "unexpected http/https/wss hosts in Redoc bundle: #{unexpected.sort.join(', ')}"
    assert_includes js, "disableTelemetry"
    assert_includes js, RecordingStudioMcp::Redoc::LOGO_MINI_TOKEN
    assert_includes js, RecordingStudioMcp::Redoc::LOGO_MINI_FULL_TOKEN
  end

  def test_javascript_for_rewrites_logo_mini_svg
    js = RecordingStudioMcp::Redoc.javascript_for("/admin/public-api/mcp-docs")

    assert_includes js, "/admin/public-api/mcp-docs/logo-mini.svg"
    assert_includes js, "/admin/public-api/mcp-docs/logo-mini-full.svg"
    refute_includes js, RecordingStudioMcp::Redoc::LOGO_MINI_TOKEN
    refute_includes js, RecordingStudioMcp::Redoc::LOGO_MINI_FULL_TOKEN
  end

  def test_license_and_assets_are_present
    dir = RecordingStudioMcp::Redoc::DIRECTORY
    license = File.read(File.join(dir, "LICENSE"))

    assert_includes license, "MIT"
    assert File.file?(File.join(dir, "logo-mini.svg"))
    assert File.file?(File.join(dir, "logo-mini-full.svg"))
    assert File.file?(File.join(dir, "THIRD_PARTY"))
    path, type = RecordingStudioMcp::Redoc.file_for("redoc.js")
    assert File.file?(path)
    assert_equal "text/javascript", type
  end

  def test_vendor_script_is_the_upgrade_path
    root = File.expand_path("..", __dir__)
    script = File.read(File.join(root, "bin/vendor-redoc"))
    readme = File.read(File.join(RecordingStudioMcp::Redoc::DIRECTORY, "README.md"))

    assert_includes script, "registry.npmjs.org/redoc"
    assert_includes script, "LOGO_MINI_TOKEN="
    assert_includes script, "cdn.redocly.com/icons"
    assert_includes readme, "bin/vendor-redoc"
  end

  private

  def host_from_url(raw)
    uri = URI.parse(raw)
    return if uri.host.blank?

    if uri.port && ![80, 443].include?(uri.port)
      "#{uri.host}:#{uri.port}"
    else
      uri.host
    end
  rescue URI::InvalidURIError
    match = raw.match(%r{(?:https?|wss)://([^/?#:]+)})
    match && match[1]
  end

  def remote_hosts(source)
    source.scan(%r{(?:https?|wss)://[^\s"'\\<>`]+}).filter_map { |raw| host_from_url(raw) }.uniq
  end
end
