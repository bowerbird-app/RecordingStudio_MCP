# frozen_string_literal: true

namespace :recording_studio_mcp do
  desc "List each MCP server's tools and sensitive flags. Fail on allow_sensitive mismatches."
  task audit: :environment do
    catalogs = RecordingStudioMcp.configuration.catalogs
    catalogs.build!
    catalogs.audit!.each { |line| puts line }
  end
end
