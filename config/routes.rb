# frozen_string_literal: true

RecordingStudioMcp::Engine.routes.draw do
  match "/", to: "mcp#handle", via: %i[get post], as: :mcp
end
