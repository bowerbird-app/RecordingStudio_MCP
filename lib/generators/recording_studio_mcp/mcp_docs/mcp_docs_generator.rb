# frozen_string_literal: true

require "rails/generators"
require_relative "mcp_docs_generator_support"

module RecordingStudioMcp
  module Generators
    class McpDocsGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :mount_path, type: :string, default: "/mcp-docs",
                                desc: "Path where the MCP documentation is mounted"
      class_option :api_surface, type: :string, default: "public",
                                 desc: "Named RecordingStudioApi surface to document"
      class_option :access, type: :string, default: "authenticated",
                            desc: "Documentation access mode: authenticated or public"
      class_option :layout, type: :string, default: nil,
                            desc: "Optional layout override for MCP documentation"

      desc "Installs routes and configuration for gem-owned MCP documentation"

      def validate_configuration
        McpDocsGeneratorSupport.validate!(self)
      end

      def add_routes
        McpDocsGeneratorSupport.write_routes(self)
      end

      def create_configuration
        McpDocsGeneratorSupport.write_configuration(self)
      end
    end
  end
end
