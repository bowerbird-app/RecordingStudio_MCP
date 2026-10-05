# frozen_string_literal: true

module RecordingStudioMcp
  module ResultShape
    SERVER_INFO_META = "io.modelcontextprotocol/serverInfo"

    module_function

    def complete(extra, protocol_version:, cacheable: true)
      payload = extra.dup
      return payload unless Configuration.modern_protocol?(protocol_version)

      shaped = { resultType: "complete" }.merge(payload)
      shaped = shaped.merge(ttlMs: 0, cacheScope: "private") if cacheable && !shaped.key?(:ttlMs)
      with_server_info(shaped)
    end

    def with_server_info(payload)
      meta = (payload[:_meta] || {}).merge(SERVER_INFO_META => Protocol.server_info)
      payload.merge(_meta: meta)
    end
  end
end
