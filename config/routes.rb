# frozen_string_literal: true

RecordingStudioMcp::Engine.routes.draw do
  match "/", to: "mcp#handle", via: %i[get post], as: :mcp
  match "/apis/:api_key", to: "mcp#handle", via: %i[get post], as: :named_api_mcp
end
