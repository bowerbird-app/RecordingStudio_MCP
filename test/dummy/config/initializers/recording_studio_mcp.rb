# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
  config.events_enabled = true
  config.event_callback_host_allowed = ->(host) { host == "receiver.example.test" }
end

RecordingStudioMcp.register_event("recording updated") do |e|
  e.on :recording_updated
  e.types "Page"
  e.if { |recording| recording.trashed_at.nil? }
end

# Custom event: fired by the host with RecordingStudioMcp.notify("page commented", recording: ...)
# (see PagesController#comment, the Ping watchers button on /pages)
RecordingStudioMcp.register_event("page commented") do |e|
  e.types "Page"
end
