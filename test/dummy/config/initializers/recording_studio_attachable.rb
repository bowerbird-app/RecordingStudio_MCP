# frozen_string_literal: true

RecordingStudioAttachable.configure do |config|
  config.allowed_content_types = ["image/*"]
  config.max_file_size = 25.megabytes
  config.max_file_count = 3
  config.enabled_attachment_kinds = %i[image]
  config.default_listing_scope = :direct
  config.default_kind_filter = :images
  config.layout = "recording_studio/default_layout"
  config.auth_roles = {
    view: :view,
    upload: :edit,
    revise: :edit,
    remove: :admin,
    restore: :admin,
    download: :view
  }
end
