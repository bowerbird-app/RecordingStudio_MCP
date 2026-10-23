# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    private

    def tools_list_result(_params, _id, _method_name)
      ResultShape.complete(
        { tools: Tools.definitions(access_grant: access_grant) },
        protocol_version: request_protocol_version
      )
    end

    def call_tool(params, id, _method_name)
      error = call_tool_error(params, id)
      return error if error

      complete_tool_call(params)
    end

    def complete_tool_call(params)
      ResultShape.complete(
        Dispatcher.call(**tool_call_args(params)),
        protocol_version: request_protocol_version,
        cacheable: false
      )
    end

    def tool_call_args(params)
      {
        tool_name: params["name"].to_s,
        arguments: params["arguments"] || {},
        access_grant: access_grant,
        idempotency_key: idempotency_key,
        request_context: request_context
      }
    end

    def call_tool_error(params, id)
      return rpc_error(id, INVALID_PARAMS, "Invalid params") unless params.is_a?(Hash)

      arguments = params["arguments"]
      return rpc_error(id, INVALID_PARAMS, "Invalid params") unless arguments.nil? || arguments.is_a?(Hash)
      return rpc_error(id, INVALID_PARAMS, "name is required") if params["name"].to_s.blank?

      nil
    end

    def skill_result(params, id, method_name)
      answer = Skills.answer(
        method_name,
        params,
        access_grant: access_grant,
        protocol_version: request_protocol_version
      )
      wrap_skill_answer(answer, id)
    end

    def wrap_skill_answer(answer, id)
      case answer
      when Skills::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Skills::Unavailable
        rpc_error(id, INTERNAL_ERROR, "Skill content is unavailable")
      when Skills::Result
        answer.payload
      else
        raise TypeError, "unexpected skill answer"
      end
    end
  end
end
