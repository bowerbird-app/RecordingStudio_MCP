# frozen_string_literal: true

module RecordingStudioMcp
  module ResultShape
    module_function

    def complete(extra, protocol_version:)
      payload = extra.dup
      return payload unless Configuration.modern_protocol?(protocol_version)

      { resultType: "complete" }.merge(payload).merge(ttlMs: 0, cacheScope: "private")
    end
  end
end
