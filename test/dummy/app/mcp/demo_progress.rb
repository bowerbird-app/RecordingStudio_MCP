# frozen_string_literal: true

class DemoProgress
  STEPS = 5

  def self.call(context, _arguments)
    STEPS.times do |index|
      break if context&.disconnected?

      context&.progress(
        current: index + 1,
        total: STEPS,
        message: "Step #{index + 1} of #{STEPS}"
      )
      sleep sleep_seconds
    end

    {
      completed: !context&.disconnected?,
      steps: STEPS
    }
  end

  def self.sleep_seconds
    ENV.fetch("MCP_DEMO_PROGRESS_SLEEP", "1").to_f
  end
end
