# frozen_string_literal: true

module RecordingStudioMcp
  module AfterCommit
    module_function

    def run(&block)
      raise ArgumentError, "block required" unless block

      if open_transaction?
        ActiveRecord::Base.current_transaction.after_commit(&block)
      else
        block.call
      end
    end

    def open_transaction?
      return false unless defined?(ActiveRecord::Base)
      return false unless ActiveRecord::Base.connected?

      transaction = ActiveRecord::Base.current_transaction
      transaction.respond_to?(:open?) && transaction.open?
    rescue StandardError
      false
    end
    private_class_method :open_transaction?
  end
end
