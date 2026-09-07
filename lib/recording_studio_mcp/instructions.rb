# frozen_string_literal: true

module RecordingStudioMcp
  module Instructions
    TEXT = <<~TEXT.squish.freeze
      Connect with the Oauth Bearer token; it intentionally authorizes both this MCP endpoint and the Recording Studio API
      through the same AccessGrant. Call describe before create or capability_action. Send writable fields at the top level,
      not under attributes. For the next list page, pass meta.next_pagination_token as pagination_token. Tool changes are not
      pushed live, so call tools/list again when you need a fresh list.
    TEXT

    module_function

    def text
      TEXT
    end
  end
end
