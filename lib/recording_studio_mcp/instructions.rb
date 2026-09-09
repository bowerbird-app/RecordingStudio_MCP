# frozen_string_literal: true

module RecordingStudioMcp
  module Instructions
    AUTH_BLURB = <<~TEXT.squish.freeze
      Connect with the Oauth Bearer token; it intentionally authorizes both this MCP endpoint and the Recording Studio API
      through the same AccessGrant.
    TEXT

    TREE_BLURB = <<~TEXT.squish.freeze
      Call describe before create or capability_action. Send writable fields at the top level,
      not under attributes. For the next list page, pass meta.next_pagination_token as pagination_token.
    TEXT

    ENDPOINT_BLURB = <<~TEXT.squish.freeze
      Use the endpoint tools. Path parameters are tool arguments.
    TEXT

    REFRESH_BLURB = <<~TEXT.squish.freeze
      Tool changes are not pushed live, so call tools/list again when you need a fresh list.
    TEXT

    module_function

    def text(access_grant: nil, surface: nil)
      surface ||= ToolSurface.for(access_grant: access_grant)
      parts = [AUTH_BLURB]
      parts << TREE_BLURB if surface.tree_enabled?
      parts << ENDPOINT_BLURB if surface.endpoints_enabled?
      parts << REFRESH_BLURB
      parts.join(" ")
    end
  end
end
