# frozen_string_literal: true

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
  config.events_enabled = true
  config.event_callback_host_allowed = ->(host) { host == "receiver.example.test" }
  config.documentation_enabled = true
  config.documentation_access = :authenticated
  config.documentation_layout_name = "recording_studio/default_layout"
end

RecordingStudioMcp.register_event("recording updated") do |e|
  e.on :recording_updated
  e.types "Page"
  e.if { |recording| recording.trashed_at.nil? }
end

# Custom event: fired by the host with RecordingStudioMcp.notify("page commented", recording: ...)
# (see PagesController#comment, the Ping watchers button on /pages)
RecordingStudioMcp.register_event("page commented") do |e|
  e.types "Page"
end

%w[Workspace Folder Page].each do |type|
  RecordingStudioMcp.register_type(
    type: type,
    description: "#{type} records nest by parent_id. root_id is the workspace. Call describe before you write."
  )
end

RecordingStudioMcp.register_tool(
  name: "ping",
  endpoint: :ping,
  title: "Ping",
  description: "Confirm this named API can reach a registered endpoint.",
  input: {},
  output: "ok"
)

RecordingStudioMcp.register_tool(
  name: RecordingStudioMcp.tool_name("Workspace", :ping),
  type: "Workspace",
  action: :ping,
  title: "Ping workspace",
  description: "Ping a workspace.",
  input: {},
  output: "ok"
)

RecordingStudioMcp.register_tool(
  name: "demo_progress",
  endpoint: :demo_progress,
  title: "Demo progress",
  description: "Dummy-only endpoint that emits delayed progress, then a final result.",
  input: {},
  output: "the progress result"
)

RecordingStudioMcp.register_tool(
  name: "ops_ping",
  endpoint: :ops_ping,
  title: "Ops ping",
  description: "Confirm the operations named API can reach a registered endpoint.",
  input: {},
  output: "ok"
)

%i[operations_metrics_index operations_metrics_show].each do |name|
  RecordingStudioMcp.register_tool(
    name: name.to_s,
    endpoint: name,
    title: name.to_s.tr("_", " ").capitalize,
    description: "Operations metrics #{name.to_s.delete_prefix('operations_metrics_')}.",
    input: {},
    output: "metrics"
  )
end

RecordingStudioMcp.register_skill(
  name: "page-desk",
  type: "Page",
  title: "Page desk",
  description: "Read and update Page records on this server.",
  body: "Use list with type Page, then show. Writes need parent_id for create.",
  tools: %w[list show create update describe]
)

RecordingStudioMcp.register_server(:public, api: :public) do
  include_tools :list, :show, :create, :update, :capability_action, :ping, :demo_progress,
                RecordingStudioMcp.tool_name("Workspace", :ping)
  include_skills "page-desk"
end

RecordingStudioMcp.register_server(:operations, api: :operations, allow_sensitive: true) do
  include_tools :list, :show, :create, :update, :delete, :capability_action, :ops_ping,
                :operations_metrics_index, :operations_metrics_show,
                "mcp_calls-over_time",
                "mcp_calls-failed_over_time",
                "mcp_calls-by_tool",
                "mcp_calls-failed_by_tool",
                "mcp_calls-by_method",
                "mcp_calls-rate_limited",
                "mcp_subscriptions-failing"
end
