# frozen_string_literal: true

module RecordingStudioMcp
  class MaintainUsageJob < ActiveJob::Base
    queue_as :recording_studio_mcp_usage

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(today: Date.current)
      MaintainUsage.call(today: today)
    end
  end
end
