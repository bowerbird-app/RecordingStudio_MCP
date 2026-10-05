# frozen_string_literal: true

module RecordingStudioMcp
  module StreamDecision
    EVENT_STREAM = "text/event-stream"

    module_function

    def stream?(method_name:, params:, accept_header:)
      method_name.to_s == "tools/call" && progress_token(params) && accept_event_stream?(accept_header)
    end

    def listen?(method_name:, protocol_version:, accept_header:)
      method_name.to_s == "subscriptions/listen" &&
        Configuration.modern_protocol?(protocol_version) &&
        accept_event_stream?(accept_header)
    end

    def legacy_get_listen?(protocol_version:, accept_header:)
      Configuration.legacy_protocol?(protocol_version) && accept_event_stream?(accept_header)
    end

    def progress_token(params)
      return unless params.is_a?(Hash)

      meta = params["_meta"] || params[:_meta]
      return unless meta.is_a?(Hash)

      token = meta.key?("progressToken") ? meta["progressToken"] : meta[:progressToken]
      return token if token.is_a?(String) || token.is_a?(Integer)

      nil
    end

    def accept_event_stream?(accept_header)
      accept_header.to_s.split(",").any? do |entry|
        entry.split(";").first.to_s.strip.downcase == EVENT_STREAM
      end
    end
  end
end
