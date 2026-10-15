# frozen_string_literal: true

module RecordingStudioMcp
  module Instructions
    AUTH_BLURB = <<~TEXT.squish.freeze
      Connect with the Oauth Bearer token; it intentionally authorizes both this MCP endpoint and the Recording Studio API
      through the same AccessGrant.
    TEXT

    METRIC_BLURB = "Recordable metric tools are read-only. Their arguments are that metric's query parameters. " \
                   "Pass list filters as a filter object of attribute names."
    CATALOG_METRIC_BLURB = "API metric tools are read-only. A timeseries takes from and to. " \
                           "start and start_at are the same as from. end and end_at are the same as to. " \
                           "Pass filters as a filters object."

    ENDPOINT_BLURB = <<~TEXT.squish.freeze
      Use the endpoint tools. Path parameters are tool arguments. Call tools/list to see
      the available endpoint tools. An endpoint-only grant has no tree or recordable tools
      such as list, show, create, update, delete, capability_action, or describe. When an endpoint
      returns a catalog or list and another returns detail for an item, fetch the detail
      before generating UI. Do not invent recordable types or assume those tree tools exist
      unless tools/list advertises them.
    TEXT

    REFRESH_BLURB = <<~TEXT.squish.freeze
      Tool changes are not pushed live, so call tools/list again when you need a fresh list.
    TEXT

    WATCH_BLURB = <<~TEXT.squish.freeze
      List and read accessible items as resources. Subscribe to a resource URI to be told when that item changes, then read it again.
    TEXT

    SKILLS_BLURB = "This server may provide skills containing additional guidance for completing tasks with these " \
                   "tools. Discover and use relevant skills when appropriate."
    WRITE_FIELDS_BLURB = "Send writable fields at the top level, not under attributes."
    PAGINATION_BLURB = "For the next list page, pass meta.next_pagination_token as pagination_token."

    module_function

    def text(access_grant: nil)
      surface = ToolSurface.for(access_grant: access_grant)
      parts = [AUTH_BLURB, *surface_blurbs(surface), REFRESH_BLURB]
      parts << WATCH_BLURB if RecordingStudioMcp.events_registered?
      parts << SKILLS_BLURB
      parts << suffix_part(access_grant: access_grant)
      parts.compact.join(" ")
    end

    def surface_blurbs(surface)
      [
        (tree_blurb(surface) if surface.tree_enabled?),
        (METRIC_BLURB if surface.recordable_metric_tools?),
        (CATALOG_METRIC_BLURB if surface.catalog_metric_tools?),
        (ENDPOINT_BLURB if surface.endpoints_enabled?)
      ]
    end

    def tree_blurb(surface)
      names = surface.tree_tool_names
      before = %w[create capability_action].select { |name| names.include?(name) }
      parts = [describe_guidance(names, before)]
      parts << WRITE_FIELDS_BLURB if names.intersect?(%w[create update])
      parts << PAGINATION_BLURB if names.include?("list")
      parts.compact.join(" ")
    end

    def describe_guidance(names, before)
      return unless names.include?("describe")
      return "Call describe for a type's allowed operations." if before.empty?

      "Call describe before #{before.join(' or ')}."
    end

    def suffix_part(access_grant:)
      source = RecordingStudioMcp.configuration.instructions_suffix
      return nil if source.nil?

      raw = source.respond_to?(:call) ? source.call(access_grant: access_grant) : source
      return nil unless raw.is_a?(String)

      text = raw.strip
      text.empty? ? nil : text
    end
    private_class_method :suffix_part, :tree_blurb, :describe_guidance, :surface_blurbs
  end
end
