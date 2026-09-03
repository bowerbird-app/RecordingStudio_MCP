# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end
