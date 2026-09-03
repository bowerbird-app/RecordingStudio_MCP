Rails.application.routes.draw do
  devise_for :users

  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"
  mount RecordingStudioAccessible::Engine, at: "/admin/access", as: :recording_studio_admin_access
  mount RecordingStudioApi::Engine, at: "/recording_studio_api"
  mount RecordingStudioOauth::Engine, at: "/recording_studio_oauth"
  mount RecordingStudioMcp::Engine, at: "/recording_studio_mcp"
  mount RecordingStudioAttachable::Engine, at: "/recording_studio_attachable"
  mount RecordingStudioSiteSettings::Engine, at: "/recording_studio_site_settings"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"

  get "/.well-known/oauth-authorization-server",
      to: "recording_studio_oauth/oauth_discoveries#authorization_server",
      defaults: { api_key: "public" }
  get "/.well-known/oauth-protected-resource",
      to: "recording_studio_oauth/oauth_discoveries#protected_resource",
      defaults: { api_key: "public" }

  recording_studio_admin_for :admin, at: "/admin", root_section: :root

  get "up" => "rails/health#show", as: :rails_health_check

  get "docs/install", to: "docs#install", as: :docs_install
  get "docs/config", to: "docs#configuration", as: :docs_config
  get "docs/recordable_types", to: "docs#recordable_types", as: :docs_recordable_types
  get "docs/recordings_tree", to: "docs#recordings_tree", as: :docs_recordings_tree
  get "docs/gem_views", to: "docs#gem_views", as: :docs_gem_views
  get "docs/methods", to: "docs#methods", as: :docs_methods
  get "docs/mcp", to: "docs#mcp", as: :docs_mcp

  root "home#index"
end
