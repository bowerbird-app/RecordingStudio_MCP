# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
  # Native clients may omit Origin. Browser clients must match the MCP host or an entry here.
  # config.allowed_origins = ["https://assistant.example"]
  # Optional String or ->(access_grant:) { ... } appended after built-in initialize instructions.
  # config.instructions_suffix = "Prefer list then show before you write."
end
