# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.default_mount_path = "/admin"
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.async_widgets.enabled = false
  config.access_recording_resolver = lambda do |context|
    RecordingStudioAccessible.admin_root(context: context)
  end
  config.layout = "recording_studio/default_layout"
end

class DummyAdminRootSection < RecordingStudioAdmin::Section
  key "root"
  title "Admin"
  blast_radius :site
  widget "oauth.active_apps"
  widget "oauth.active_connections"
  link :oauth_apps, text: "Registered apps", url: ->(context) { context.admin_section_path("oauth_apps") }
  link :mcp, text: "MCP", url: ->(context) { context.admin_section_path("mcp") }
end

Rails.application.config.to_prepare do
  RecordingStudioAdmin.register_section(DummyAdminRootSection)
  RecordingStudioAdmin::ApplicationController.helper RecordingStudioLegacyPageNavHelper
end
