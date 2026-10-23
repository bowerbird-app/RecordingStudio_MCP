# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    private

    def events_result(params, id, method_name)
      return rpc_error(id, METHOD_NOT_FOUND, "Method not found") unless RecordingStudioMcp.configuration.events_enabled

      wrap_events_answer(event_rpc_answer(method_name, params), id)
    end

    def event_rpc_answer(method_name, params)
      case method_name
      when "events/list"
        EventRpc.list(params: params, protocol_version: request_protocol_version)
      when "events/subscribe"
        EventRpc.subscribe(params: params, access_grant: access_grant, protocol_version: request_protocol_version)
      else
        EventRpc.unsubscribe(params: params, access_grant: access_grant)
      end
    end

    def wrap_events_answer(answer, id)
      case answer
      when EventRpc::Error
        rpc_error(id, answer.code, answer.message, data: answer.data)
      when EventRpc::Answer
        answer.payload
      else
        raise TypeError, "unexpected events answer"
      end
    end
  end
end
