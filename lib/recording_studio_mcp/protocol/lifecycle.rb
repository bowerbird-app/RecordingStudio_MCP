# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    private

    def initialize_result(params, id, _method_name)
      version = negotiated_version(params["protocolVersion"].to_s)
      session_id = open_legacy_session(version)
      Result.new(status: :ok, notification: false, session_id: session_id, body: initialize_body(id, version))
    end

    def negotiated_version(requested)
      return requested if Configuration::SUPPORTED_PROTOCOL_VERSIONS.include?(requested)

      RecordingStudioMcp.configuration.protocol_version
    end

    def initialize_body(id, version)
      {
        jsonrpc: JSONRPC_VERSION,
        id: id,
        result: {
          protocolVersion: version,
          capabilities: server_capabilities,
          serverInfo: self.class.server_info,
          instructions: Instructions.text(access_grant: access_grant)
        }
      }
    end

    def discover_result(_params, _id, _method_name)
      ResultShape.complete(
        {
          supportedVersions: Configuration::SUPPORTED_PROTOCOL_VERSIONS,
          capabilities: server_capabilities,
          instructions: Instructions.text(access_grant: access_grant)
        },
        protocol_version: Configuration::MODERN_PROTOCOL_VERSION
      )
    end

    def ok_notification(_params, _id, _method_name)
      :ok
    end

    def ping_result(_params, _id, _method_name)
      ResultShape.complete({}, protocol_version: request_protocol_version, cacheable: false)
    end

    def server_capabilities
      capabilities = {
        tools: { listChanged: false },
        resources: resources_capability,
        extensions: { "io.modelcontextprotocol/skills" => {} }
      }
      capabilities[:events] = {} if RecordingStudioMcp.configuration.events_enabled
      capabilities
    end

    def resources_capability
      RecordingStudioMcp.events_registered? ? { subscribe: true } : {}
    end

    def open_legacy_session(version)
      return unless Configuration.legacy_protocol?(version)
      return unless request_context

      connection = Connections.open(protocol_version: version, access_grant: access_grant)
      request_context.attach_connection(connection)
      connection.id
    end
  end
end
