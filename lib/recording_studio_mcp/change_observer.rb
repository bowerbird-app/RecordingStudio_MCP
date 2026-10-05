# frozen_string_literal: true

module RecordingStudioMcp
  module ChangeObserver
    module_function

    def install!
      return unless defined?(RecordingStudio)

      hooks = RecordingStudio.configuration.hooks
      return if @installed.equal?(hooks)

      hooks.after_record(self)
      @installed = hooks
    end

    def call(event)
      AfterCommit.run { Notifier.recording_saved(event) }
    end
  end
end
