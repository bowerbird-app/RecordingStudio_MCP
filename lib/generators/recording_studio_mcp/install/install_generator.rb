# frozen_string_literal: true

require "rails/generators"

module RecordingStudioMcp
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudioMcp into your application"

      class_option(
        :mount_path,
        type: :string,
        default: "/recording_studio_mcp",
        desc: "Route prefix used when mounting the engine"
      )

      def mount_engine
        route %(mount RecordingStudioMcp::Engine, at: "#{options[:mount_path]}")
      end

      def copy_initializer
        template "recording_studio_mcp_initializer.rb", "config/initializers/recording_studio_mcp.rb"
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
