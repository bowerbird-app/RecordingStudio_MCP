# frozen_string_literal: true

namespace :recording_studio_mcp do
  desc "List each MCP server's tools and sensitive flags. Fail on allow_sensitive mismatches."
  task audit: :environment do
    lines = RecordingStudioMcp.configuration.catalogs.audit!
    lines.each { |line| puts line }
  end
end
