# frozen_string_literal: true

module RecordingStudioMcp
  module Generators
    module McpDocsGeneratorConfig
      INITIALIZER = "config/initializers/recording_studio_mcp_docs.rb"

      module_function

      def write(generator)
        return if generator.behavior == :revoke

        path = File.join(generator.destination_root, INITIALIZER)
        if File.exist?(path)
          generator.say(skip_message, :yellow)
          return
        end

        generator.create_file(INITIALIZER, source(generator))
      end

      def validation_errors(generator)
        errors = []
        errors << "NAME must contain letters, numbers, underscores, dashes, or slashes" unless valid_name?(generator)
        errors << "--mount-path must be a safe absolute path" unless valid_path?(mount_path(generator))
        errors << "--api-surface must contain letters, numbers, underscores, or dashes" unless valid_api?(generator)
        errors << "--access must be authenticated or public" unless valid_access?(generator)
        errors << "--layout must be a layout name" unless valid_layout?(generator)
        errors
      end

      def source(generator)
        layout = generator.options[:layout]
        layout_line = layout.present? ? "\n  config.documentation_layout_name = #{layout.to_s.inspect}" : ""
        <<~RUBY
          # frozen_string_literal: true

          RecordingStudioMcp.configure do |config|
            config.documentation_enabled = true
            config.documentation_access = :#{access_mode(generator)}#{layout_line}
          end
        RUBY
      end

      def skip_message
        "MCP docs configuration already exists. Every MCP docs route shares " \
          "documentation_enabled and documentation_access. Skipping #{INITIALIZER}."
      end

      def mount_path(generator)
        path = generator.options[:mount_path].to_s.strip
        path = "/#{path}" unless path.start_with?("/")
        path.squeeze("/").sub(%r{/\z}, "").presence || "/"
      end

      def access_mode(generator)
        generator.options[:access].to_s.strip.downcase
      end

      def valid_name?(generator)
        name = generator.name.to_s
        name.match?(%r{\A[a-zA-Z][a-zA-Z0-9_/-]*\z}) && !name.include?("..")
      end

      def valid_path?(path)
        path.match?(%r{\A/[a-zA-Z0-9._~!$&'+,;=@/-]*\z}) && !path.include?("..") && !path.include?("//") && path != "/"
      end

      def valid_api?(generator)
        generator.options[:api_surface].to_s.strip.downcase.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)
      end

      def valid_access?(generator)
        %w[authenticated public].include?(access_mode(generator))
      end

      def valid_layout?(generator)
        layout = generator.options[:layout]
        layout.blank? || layout.to_s.match?(%r{\A[a-zA-Z][a-zA-Z0-9_/-]*\z})
      end
    end
  end
end
