# frozen_string_literal: true

require_relative "mcp_docs_generator_config"

module RecordingStudioMcp
  module Generators
    module McpDocsGeneratorRoutes
      ROUTES = "config/routes.rb"

      module_function

      def write(generator)
        return remove_route_block(generator) if generator.behavior == :revoke

        path = File.join(generator.destination_root, ROUTES)
        unless File.exist?(path)
          raise Thor::Error, "MCP documentation generator failed: config/routes.rb was not found."
        end

        apply_route_block(generator, File.read(path))
      end

      def apply_route_block(generator, source)
        block = route_block(generator)
        start = route_start_marker(generator)
        if source.include?(start)
          if source.include?(block.strip)
            generator.say("MCP documentation routes already exist for #{generator.name}.", :yellow)
            return
          end

          raise Thor::Error, differing_route_message(generator)
        end

        generator.inject_into_file ROUTES, "\n#{block}", before: /\nend\s*\z/
      end

      def remove_route_block(generator)
        path = File.join(generator.destination_root, ROUTES)
        return unless File.exist?(path)

        source = File.read(path)
        start = route_start_marker(generator)
        finish = route_end_marker(generator)
        pattern = /\n?#{Regexp.escape(start)}.*?#{Regexp.escape(finish)}\n?/m
        updated = source.gsub(pattern, "")
        if source == updated
          generator.say("No MCP documentation route block found for #{generator.name}.", :yellow)
          return
        end

        generator.say_status :remove, ROUTES
        File.write(path, updated) unless generator.options[:pretend]
      end

      def differing_route_message(generator)
        "MCP documentation generator failed: existing route block for " \
          "#{generator.name} differs from this configuration."
      end

      def api_name(generator)
        generator.options[:api_surface].to_s.strip.downcase
      end

      def route_key(generator)
        generator.file_name.tr("/", "_").parameterize(separator: "_")
      end

      def route_start_marker(generator)
        "# BEGIN RecordingStudioMcp docs: #{route_key(generator)}"
      end

      def route_end_marker(generator)
        "# END RecordingStudioMcp docs: #{route_key(generator)}"
      end

      def route_block(generator)
        path = McpDocsGeneratorConfig.mount_path(generator)
        <<~RUBY
          #{route_start_marker(generator)}
          recording_studio_mcp_docs_for :#{api_name(generator)},
            at: #{path.inspect},
            as: :#{route_key(generator)}_mcp_docs
          #{route_end_marker(generator)}
        RUBY
      end
    end
  end
end
