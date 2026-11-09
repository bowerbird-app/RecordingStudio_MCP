# frozen_string_literal: true

module RecordingStudioMcp
  class ApplicationController < ActionController::Base
    if defined?(RecordingStudio::RootSwitchable::ControllerSupport)
      include RecordingStudio::RootSwitchable::ControllerSupport
    end
    include RecordingStudio::ControllerLayout

    protect_from_forgery with: :exception
  end
end
