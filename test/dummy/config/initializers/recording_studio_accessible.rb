# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [
    "User",
    "RecordingStudioApi::ApiClient",
    "RecordingStudioOauth::OauthAuthorization"
  ]

  # Site screens resolve only when this kept root is the access recording.
  config.admin_root_resolver = lambda do |context: nil|
    admin_root = AdminRoot.find_by(name: "Admin")
    next unless admin_root

    RecordingStudio::Recording.kept.find_by(recordable: admin_root, parent_recording_id: nil)
  end
end
