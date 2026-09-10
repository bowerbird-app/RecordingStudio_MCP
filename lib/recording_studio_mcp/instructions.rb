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
      Use the endpoint tools. Path parameters are tool arguments. Call tools/list to see
      the available endpoint tools. An endpoint-only grant has no tree or recordable tools
      such as list, show, create, update, capability_action, or describe. When an endpoint
      returns a catalog or list and another returns detail for an item, fetch the detail
      before generating UI. Do not invent recordable types or assume those tree tools exist
      unless tools/list advertises them.
    TEXT

    REFRESH_BLURB = <<~TEXT.squish.freeze
      Tool changes are not pushed live, so call tools/list again when you need a fresh list.
    TEXT

    module_function

    def text(access_grant: nil)
      surface = ToolSurface.for(access_grant: access_grant)
      parts = [AUTH_BLURB]
      parts << TREE_BLURB if surface.tree_enabled?
      parts << ENDPOINT_BLURB if surface.endpoints_enabled?
      parts << REFRESH_BLURB
      suffix = suffix_part(access_grant: access_grant)
      parts << suffix if suffix
      parts.join(" ")
    end

    def suffix_part(access_grant:)
      source = RecordingStudioMcp.configuration.instructions_suffix
      return nil if source.nil?

      raw = source.respond_to?(:call) ? source.call(access_grant: access_grant) : source
      return nil unless raw.is_a?(String)

      text = raw.strip
      text.empty? ? nil : text
    end
    private_class_method :suffix_part
  end
end
