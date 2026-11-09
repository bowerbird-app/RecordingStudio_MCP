# frozen_string_literal: true

require_relative "mcp_docs_generator_routes"
require_relative "mcp_docs_generator_config"

module RecordingStudioMcp
  module Generators
    module McpDocsGeneratorSupport
      module_function

      def validate!(generator)
        errors = McpDocsGeneratorConfig.validation_errors(generator)
        return if errors.empty?

        raise Thor::Error, "MCP documentation generator failed: #{errors.join('; ')}"
      end

      def write_routes(generator)
        McpDocsGeneratorRoutes.write(generator)
      end

      def write_configuration(generator)
        McpDocsGeneratorConfig.write(generator)
      end
    end
  end
end
