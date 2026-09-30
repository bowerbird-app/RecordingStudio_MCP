# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module Admin
    ServerWidget = RecordingStudioAdmin::Widget.new("mcp.server") do
      type :list
      title "Server"
      info "Name, version, and the paths clients use."
      hide_change
      hide_period
      blast_radius :site
      items { RecordingStudioMcp::Admin.server_items }
    end

    ToolsWidget = RecordingStudioAdmin::Widget.new("mcp.tools") do
      type :list
      title "Tools"
      info "What this server can do."
      hide_change
      hide_period
      blast_radius :site
      items { RecordingStudioMcp::Admin.tool_items }
    end

    SkillsWidget = RecordingStudioAdmin::Widget.new("mcp.skills") do
      type :list
      title "Skills"
      info "Registered here. Exposed is what a new client is offered."
      hide_change
      hide_period
      blast_radius :site
      items { RecordingStudioMcp::Admin.skill_items }
    end

    InstructionsWidget = RecordingStudioAdmin::Widget.new("mcp.instructions") do
      type :list
      title "Instructions"
      info "Sent when a client connects."
      hide_change
      hide_period
      blast_radius :site
      items { RecordingStudioMcp::Admin.instruction_items }
    end

    class McpSection < RecordingStudioAdmin::Section
      # A second load reopens this class. widget and link append, so clear them first.
      @widget_keys_value = []
      @links_value = []

      key "mcp"
      title "MCP"
      subtitle "What clients are offered."
      blast_radius :site
      widget "mcp.server"
      widget "mcp.tools"
      widget "mcp.skills"
      widget "mcp.instructions"
      link :oauth_apps, text: "Registered apps", url: ->(context) { context.admin_section_path("oauth_apps") }
    end

    module_function

    def server_items
      info = Protocol.server_info
      paths = ProtectedResourceMetadata
      [
        { leading: "Name", text: info.fetch(:name) },
        { leading: "Version", text: info.fetch(:version) },
        { leading: "Protocol", text: RecordingStudioMcp.configuration.protocol_version },
        { leading: "Endpoint", text: paths.mcp_mount_path },
        { leading: "Discovery", text: paths.well_known_path },
        { leading: "Oauth", text: paths.oauth_engine_mount_path }
      ]
    end

    def tool_items
      tools = Tools.definitions(api: nil)
      return [{ text: "None" }] if tools.empty?

      tools.map { |tool| { text: tool.fetch(:name), trailing: tool.fetch(:title) } }
    rescue RecordingStudioApi::ConfigurationError => e
      [{ text: "Tools could not be listed. #{e.message}" }]
    end

    def skill_items
      catalog = RecordingStudioMcp.configuration.skill_catalog
      return [{ text: "None" }] if catalog.none?

      exposed_names = RecordingStudioMcp.exposed_skills(access_grant: nil).map(&:name)
      catalog.map do |registration|
        trailing = exposed_names.include?(registration.name) ? "Registered, exposed" : "Registered only"
        { text: registration.name, trailing: trailing }
      end
    end

    def instruction_items
      # Instructions.text builds the same tool surface as Tools.definitions.
      [{ text: Instructions.text(access_grant: nil) }]
    rescue RecordingStudioApi::ConfigurationError => e
      [{ text: "Instructions could not be loaded. #{e.message}" }]
    end

    def register!
      RecordingStudioAdmin.register_widget(ServerWidget)
      RecordingStudioAdmin.register_widget(ToolsWidget)
      RecordingStudioAdmin.register_widget(SkillsWidget)
      RecordingStudioAdmin.register_widget(InstructionsWidget)
      RecordingStudioAdmin.register_section(McpSection)
    end
  end
end
