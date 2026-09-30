# frozen_string_literal: true

namespace :recording_studio_mcp do
  desc "Rebuild recent MCP usage totals and delete raw logs older than 30 days"
  task maintain_usage: :environment do
    result = RecordingStudioMcp::MaintainUsage.call
    puts "Aggregated #{result[:aggregated_dates].map(&:iso8601).join(', ')}. Pruned #{result[:pruned_logs]} logs."
  end
end
