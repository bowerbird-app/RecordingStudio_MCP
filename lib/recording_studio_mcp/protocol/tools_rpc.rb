# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioMcp
  class Protocol
    private

    def tools_list_result(_params, _id, _method_name)
      tools = Tools.definitions(access_grant: access_grant)
      remember_tool_list(tools)
      ResultShape.complete(
        { tools: tools },
        protocol_version: request_protocol_version
      )
    end

    def call_tool(params, id, _method_name)
      error = call_tool_error(params, id)
      return error if error

      remember_tool_list(Tools.definitions(access_grant: access_grant))
      complete_tool_call(params)
    end

    def remember_tool_list(tools)
      request_context&.connection&.note_tools_list!(tools_fingerprint(tools))
    end

    def tools_fingerprint(tools)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize_tools(tools)))
    end

    def canonicalize_tools(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), out| out[key.to_s] = canonicalize_tools(item) }.sort.to_h
      when Array
        value.map { |item| canonicalize_tools(item) }
      else
        value.is_a?(Symbol) ? value.to_s : value
      end
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
