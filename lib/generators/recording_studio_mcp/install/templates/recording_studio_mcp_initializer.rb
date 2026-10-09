# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
  # Native clients may omit Origin. Browser clients must match the MCP host or an entry here.
  # config.allowed_origins = ["https://assistant.example"]
  # Optional String or ->(access_grant:) { ... } appended after built-in initialize instructions.
  # config.instructions_suffix = "Prefer list then show before you write."
  # ChatGPT MCP Events (webhook delivery). Off by default. Generate migrations, migrate, then enable.
  # config.events_enabled = true
  # config.event_subscription_ttl = 24.hours
  # config.event_subscriptions_per_principal = 50
  # config.event_callback_host_allowed = ->(host) { host.end_with?(".example") }
end

# Optional. MCP UI is not a dependency of this gem. When RecordingStudio::MCP_UI
# is loaded, MCP fills empty visibility_checker and action_executor hooks.
# Hosts may replace them. action_executor should call
# RecordingStudioMcp.dispatch_widget_action.

# Optional. Register events that may notify subscribed MCP clients.
# RecordingStudioMcp.register_event("recording updated")
# RecordingStudioMcp.register_event("recording updated") do |event|
#   event.on :recording_updated
#   event.types "Page", "Document"
#   event.if { |recording| recording.published? }
# end
# RecordingStudioMcp.register_event("comment added")
# RecordingStudioMcp.notify("comment added", recording: comment.recording)
