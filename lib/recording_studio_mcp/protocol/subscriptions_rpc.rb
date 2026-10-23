# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    private

    def subscribe_enabled?
      RecordingStudioMcp.events_registered?
    end

    def subscribe_resource(params, id, _method_name)
      blocked = subscribe_blocked(id)
      return blocked if blocked

      uri = params["uri"].to_s
      return missing_resource(id, uri) unless Resources.accessible?(access_grant, uri)

      connection = request_context&.connection
      return rpc_error(id, INVALID_PARAMS, "No listening session") if connection.nil?

      connection.subscribe(uri)
      {}
    end

    def unsubscribe_resource(params, id, _method_name)
      blocked = subscribe_blocked(id)
      return blocked if blocked

      connection = request_context&.connection
      return rpc_error(id, INVALID_PARAMS, "No listening session") if connection.nil?

      connection.unsubscribe(params["uri"].to_s)
      {}
    end

    def subscribe_blocked(id)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless subscribe_enabled?
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") if modern_request?

      nil
    end

    def missing_resource(id, uri)
      rpc_error(id, RESOURCE_NOT_FOUND, "Resource not found", data: { uri: uri })
    end

    def listen_subscriptions(params, id, _method_name)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless subscribe_enabled?
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless modern_request?

      connection = open_listen_connection(id, listen_uris(params))
      request_context&.attach_connection(connection)
      Result.new(status: :ok, body: nil, notification: false, listen: true, listen_connection: connection)
    end

    def listen_uris(params)
      Array((params["notifications"] || {})["resourceSubscriptions"]).map(&:to_s).select do |uri|
        Resources.accessible?(access_grant, uri)
      end
    end

    def open_listen_connection(id, uris)
      connection = Connections.open(
        protocol_version: request_protocol_version,
        access_grant: access_grant,
        subscription_id: id
      )
      uris.each { |uri| connection.subscribe(uri) }
      connection
    end
  end
end
