# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end

RecordingStudioMcp.register_event("recording updated") do |event|
  event.on :recording_updated
end

RecordingStudioMcp.register_event("page commented")
