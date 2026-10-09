# frozen_string_literal: true

module RecordingStudioMcp
  module WidgetResult
    module_function

    def wrap(result)
      payload = result[:structuredContent]
      shaped =
        if result[:isError]
          { "ok" => false, "data" => nil, "errors" => { "base" => [result.dig(:content, 0, :text).to_s] } }
        else
          { "ok" => true, "data" => payload, "errors" => {}, "contextUpdate" => payload }
        end
      result.merge(structuredContent: shaped)
    end

    def failure(message, key: "base")
      {
        content: [{ type: "text", text: message }],
        structuredContent: { "ok" => false, "data" => nil, "errors" => { key => [message] } },
        isError: true
      }
    end
  end
end
