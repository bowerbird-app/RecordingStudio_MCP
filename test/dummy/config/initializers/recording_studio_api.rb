# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  config.openapi_title = "Recording Studio API"
  config.openapi_description = "Resource server for Recording Studio. MCP calls the same actions."
  config.documentation_enabled = true
  config.documentation_access = :public
  config.layout_name = "recording_studio/default_layout"
  config.admin_layout_name = "recording_studio/default_layout"
  config.rate_limit_oauth_enabled = false if config.respond_to?(:rate_limit_oauth_enabled=)
  config.rate_limit_api_pre_auth_enabled = false if config.respond_to?(:rate_limit_api_pre_auth_enabled=)
  config.rate_limit_api_enabled = false if config.respond_to?(:rate_limit_api_enabled=)
  config.api_request_logging_enabled = false if config.respond_to?(:api_request_logging_enabled=)
  config.api_management_authorization_required = false if config.respond_to?(:api_management_authorization_required=)
end

RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name],
  writable_attributes: %i[name],
  operations: %i[index show create update],
  capability_actions: %i[ping]
)

RecordingStudioApi.register_recordable_type_api(
  "Folder",
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name],
  writable_attributes: %i[name],
  operations: %i[index show create update]
)

RecordingStudioApi.register_recordable_type_api(
  "Page",
  serializer: ->(recordable, **) { { title: recordable.title } },
  output_keys: %i[title],
  writable_attributes: %i[title],
  operations: %i[index show create update]
)

module Dummy
  class PingWorkspace
    def self.call(context)
      context.access_grant.authorize!(recording: context.recording, role: :view)
      { json: { ok: true, id: context.recording.id } }
    end
  end
end

RecordingStudioApi.register_capability_action(
  :ping,
  capability: :accessible,
  version: "1.0.0",
  http_verb: :post,
  required_role: :view,
  handler: Dummy::PingWorkspace
)
