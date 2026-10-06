# frozen_string_literal: true

class McpEventReceiversController < ApplicationController
  def index
    @deliveries = Dummy::McpEventInbox.deliveries
  end
end
