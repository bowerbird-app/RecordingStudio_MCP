# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.default_mount_path = "/admin"
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.async_widgets.enabled = false
  config.access_recording_resolver = lambda do |_context|
    admin_root = AdminRoot.find_by(name: "Admin")
    next unless admin_root

    RecordingStudio::Recording.find_by(recordable: admin_root, parent_recording_id: nil, trashed_at: nil)
  end
  config.site_admin_recording_resolver = config.access_recording_resolver
  config.engine_layout = "recording_studio/default_layout"
end

class DummyAdminRootSection < RecordingStudioAdmin::Section
  key "root"
  title "Admin"
  blast_radius :site
  widget "oauth.active_apps"
  widget "oauth.active_connections"
  link :oauth_apps, text: "Registered apps", url: ->(context) { context.admin_section_path("oauth_apps") }
end

Rails.application.config.to_prepare do
  RecordingStudioAdmin.register_section(DummyAdminRootSection)
end
