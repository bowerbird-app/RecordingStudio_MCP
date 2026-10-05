# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end

Rails.application.config.to_prepare do
  RecordingStudioMcp.register_host_tool(
    name: "demo_progress",
    title: "Demo progress",
    description: "Dummy-only tool that emits delayed progress notifications, then a final result.",
    read_only: true,
    idempotent: true,
    handler: DemoProgress
  )
end
