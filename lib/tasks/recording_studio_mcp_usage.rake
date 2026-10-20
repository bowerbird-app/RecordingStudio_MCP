# frozen_string_literal: true

namespace :recording_studio_mcp do
  desc "Rebuild recent MCP usage totals and delete raw logs older than 30 days"
  task maintain_usage: :environment do
    result = RecordingStudioMcp::MaintainUsage.call
    puts "Aggregated #{result[:aggregated_dates].map(&:iso8601).join(', ')}. Pruned #{result[:pruned_logs]} logs."
  end

  namespace :usage_logs do
    desc "Rebuild Logs daily MCP usage summaries for FROM..TO (inclusive UTC days)"
    task backfill_summaries: :environment do
      from = Date.iso8601(ENV.fetch("FROM"))
      to = Date.iso8601(ENV.fetch("TO"))
      RecordingStudioMcp::RebuildUsageSummaries.backfill!(from: from, to: to)
      puts "Rebuilt MCP usage summaries from #{from} to #{to}"
    end
  end
end
