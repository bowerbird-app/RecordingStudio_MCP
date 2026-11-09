# frozen_string_literal: true

require "rails/generators"
require "fileutils"

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
        errors = []
        errors << "NAME must contain letters, numbers, underscores, dashes, or slashes" unless valid_name?
        errors << "--mount-path must be a safe absolute path" unless valid_path?(mount_path)
        unless api_name.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)
          errors << "--api-surface must contain letters, numbers, underscores, or dashes"
        end
        errors << "--access must be authenticated or public" unless %w[authenticated public].include?(access_mode)
        errors << "--layout must be a layout name" unless valid_layout?

        raise Thor::Error, "MCP documentation generator failed: #{errors.join('; ')}" if errors.any?
      end

      def add_routes
        return remove_marked_route_block if behavior == :revoke
        unless File.exist?(routes_file_path)
          raise Thor::Error, "MCP documentation generator failed: config/routes.rb was not found."
        end

        source = File.read(routes_file_path)
        if source.include?(route_start_marker)
          if source.include?(route_block.strip)
            return say("MCP documentation routes already exist for #{name}.", :yellow)
          end

          raise Thor::Error,
                "MCP documentation generator failed: existing route block for #{name} differs from this configuration."
        end

        inject_into_file routes_path, "\n#{route_block}", before: /\nend\s*\z/
      end

      def create_configuration
        if behavior == :revoke
          configuration_file = File.join(destination_root, configuration_path)
          if File.exist?(configuration_file)
            say_status :remove, configuration_path
            FileUtils.rm_f(configuration_file) unless options[:pretend]
          end
          return
        end

        create_file configuration_path, configuration_source
      end

      private

      def mount_path
        @mount_path ||= normalized_path(options[:mount_path])
      end

      def api_name
        options[:api_surface].to_s.strip.downcase
      end

      def access_mode
        options[:access].to_s.strip.downcase
      end

      def route_key
        @route_key ||= file_name.tr("/", "_").parameterize(separator: "_")
      end

      def route_start_marker
        "# BEGIN RecordingStudioMcp docs: #{route_key}"
      end

      def route_end_marker
        "# END RecordingStudioMcp docs: #{route_key}"
      end

      def route_block
        <<~RUBY
          #{route_start_marker}
          recording_studio_mcp_docs_for :#{api_name},
            at: #{mount_path.inspect},
            as: :#{route_key}_mcp_docs
          #{route_end_marker}
        RUBY
      end

      def configuration_path
        "config/initializers/recording_studio_mcp_docs_#{route_key}.rb"
      end

      def configuration_source
        layout_assignment = if options[:layout].present?
                              "\n  config.documentation_layout_name = #{options[:layout].to_s.inspect}"
                            else
                              ""
                            end

        <<~RUBY
          # frozen_string_literal: true

          RecordingStudioMcp.configure do |config|
            config.documentation_enabled = true
            config.documentation_access = :#{access_mode}#{layout_assignment}
          end
        RUBY
      end

      def routes_path
        "config/routes.rb"
      end

      def routes_file_path
        File.join(destination_root, routes_path)
      end

      def normalized_path(value)
        path = value.to_s.strip
        path = "/#{path}" unless path.start_with?("/")
        path.squeeze("/").sub(%r{/\z}, "").presence || "/"
      end

      def valid_name?
        name.to_s.match?(%r{\A[a-zA-Z][a-zA-Z0-9_/-]*\z}) && !name.to_s.include?("..")
      end

      def valid_path?(path)
        path.match?(%r{\A/[a-zA-Z0-9._~!$&'+,;=@/-]*\z}) && !path.include?("..") && !path.include?("//") && path != "/"
      end

      def valid_layout?
        options[:layout].blank? || options[:layout].to_s.match?(%r{\A[a-zA-Z][a-zA-Z0-9_/-]*\z})
      end

      def remove_marked_route_block
        return unless File.exist?(routes_file_path)

        source = File.read(routes_file_path)
        pattern = /\n?#{Regexp.escape(route_start_marker)}.*?#{Regexp.escape(route_end_marker)}\n?/m
        updated_source = source.gsub(pattern, "")
        return say("No MCP documentation route block found for #{name}.", :yellow) if source == updated_source

        say_status :remove, routes_path
        File.write(routes_file_path, updated_source) unless options[:pretend]
      end
    end
  end
end
