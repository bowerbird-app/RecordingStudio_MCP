# frozen_string_literal: true

class DemoProgress
  STEPS = 5

  def self.call(context)
    STEPS.times do |index|
      break if context.cancelled?

      context.progress(
        current: index + 1,
        total: STEPS,
        message: "Step #{index + 1} of #{STEPS}"
      )
      sleep sleep_seconds
    end

    {
      completed: !context.cancelled?,
      steps: STEPS
    }
  end

  def self.sleep_seconds
    ENV.fetch("MCP_DEMO_PROGRESS_SLEEP", "1").to_f
  end
end
