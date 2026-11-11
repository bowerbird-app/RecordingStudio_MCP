# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      OPENAPI_VERSION = "3.1.0"

      module Internals
        module_function

        def stringify(value)
          return value.deep_stringify_keys if value.respond_to?(:deep_stringify_keys)
          return value.as_json if value.respond_to?(:as_json)

          value
        end

        def servers(api_key)
          [{ "url" => NamedApi.mcp_path(api_key), "description" => "Streamable HTTP MCP" }]
        end
      end
      private_constant :Internals
    end
  end
end

require_relative "openapi/mcp"
require_relative "openapi/type_actions"
require_relative "openapi/schemas"

module RecordingStudioMcp
  module Documentation
    module Openapi
      module_function

      def document(page)
        spec = {
          "openapi" => OPENAPI_VERSION,
          "info" => info(page),
          "servers" => servers(page.api_key),
          "paths" => {},
          "components" => { "schemas" => Schemas.for(page) },
          "x-mcp" => Mcp.section(page)
        }
        ToolDocs.attach_sidebar!(spec, page)
        spec
      end

      def info(page)
        {
          "title" => page.title,
          "version" => RecordingStudioMcp::VERSION,
          "description" => page.overview.to_s
        }
      end

      def servers(api_key)
        Internals.servers(api_key)
      end

      def stringify(value)
        Internals.stringify(value)
      end

      private_class_method :info, :servers, :stringify
    end
  end
end
