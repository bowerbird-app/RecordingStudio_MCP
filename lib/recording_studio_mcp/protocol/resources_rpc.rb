# frozen_string_literal: true

module RecordingStudioMcp
  class Protocol
    private

    def resources_list(params, id, _method_name)
      wrap_resources_list(
        Resources.list(
          access_grant: access_grant,
          cursor: params["cursor"],
          protocol_version: request_protocol_version
        ),
        id
      )
    end

    def wrap_resources_list(answer, id)
      case answer
      when Resources::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Resources::List
        answer.payload
      else
        raise TypeError, "unexpected resources list answer"
      end
    end

    def resources_templates(params, id, _method_name)
      answer = Resources.templates(cursor: params["cursor"], protocol_version: request_protocol_version)
      wrap_resources_templates(answer, id)
    end

    def wrap_resources_templates(answer, id)
      case answer
      when Resources::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Resources::Templates
        answer.payload
      else
        raise TypeError, "unexpected resources templates answer"
      end
    end

    def resources_read(params, id, _method_name)
      uri = params["uri"]
      return skill_result(params, id, "resources/read") if Skills::SkillName.from_uri(uri)

      wrap_resources_read(
        Resources.read(access_grant: access_grant, uri: uri, protocol_version: request_protocol_version),
        id
      )
    end

    def wrap_resources_read(answer, id)
      case answer
      when Resources::InvalidParams
        rpc_error(id, INVALID_PARAMS, "Invalid params")
      when Resources::NotFound
        rpc_error(id, resource_not_found_code, "Resource not found", data: { uri: answer.uri })
      when Resources::Read
        answer.payload
      else
        raise TypeError, "unexpected resources read answer"
      end
    end

    def resource_not_found_code
      modern_request? ? INVALID_PARAMS : RESOURCE_NOT_FOUND
    end
  end
end
