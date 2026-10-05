# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/oauth_dummy_helpers"

module ConnectionCleanup
  def teardown
    RecordingStudioMcp::Connections.clear!
    super
  end
end

module ActiveSupport
  class TestCase
    prepend ConnectionCleanup
  end
end
