# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module Admin
    class McpSection < RecordingStudioAdmin::Section
      # A second load reopens this class. link appends, so clear the lists first.
      @widget_keys_value = []
      @links_value = []

      key "mcp"
      title "MCP admin"
      subtitle "What clients are offered."
      blast_radius :site
      link :oauth_apps, text: "Registered apps", url: ->(context) { context.admin_section_path("oauth_apps") }
    end

    module_function

    def register!
      RecordingStudioAdmin.register_section(McpSection)
    end
  end
end
