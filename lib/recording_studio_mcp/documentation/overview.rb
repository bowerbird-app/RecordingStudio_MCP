# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Overview
      module_function

      def markdown(surface)
        [
          intro,
          authentication,
          records_and_parents(surface),
          listing_and_pagination(surface),
          metrics(surface),
          endpoint_tools(surface),
          live_updates,
          skills
        ].compact.join("\n\n")
      end

      def intro
        "Live tools for this API. Same access as the JSON API. Browse types and tools in the sidebar."
      end

      def authentication
        <<~MD.strip
          ## Authentication

          - Connect with an OAuth Bearer token.
          - That token works here and on the JSON API.
          - Access follows the same grant as the rest of the product.
        MD
      end

      def records_and_parents(surface)
        return unless surface.tree_enabled?

        bullets = [
          "- Records nest under `parent_id`.",
          "- `root_id` is the workspace, not the parent record.",
          "- Each type in the sidebar lists allowed operations, writable fields, and actions."
        ]
        if surface.tree_tool_names.intersect?(%w[create update])
          bullets << "- Send writable fields at the top level, not under `attributes`."
        end
        ["## Records and parents", *bullets].join("\n")
      end

      def listing_and_pagination(surface)
        return unless surface.tree_tool_names.include?("list")

        bullets = [
          "- `list` returns `records` and `meta`.",
          "- Pass `meta.next_pagination_token` as `pagination_token` for the next page."
        ]
        bullets << "- Walk down with `list` and `parent_id`, then `show`." if surface.list_parent_id?
        ["## Listing and pagination", *bullets].join("\n")
      end

      def metrics(surface)
        bullets = []
        if surface.recordable_metric_tools?
          bullets << "- Type metric tools are read-only. Arguments are that metric's query parameters."
          bullets << "- Pass list filters as a `filter` object of field names."
        end
        if surface.catalog_metric_tools?
          bullets << "- API metric tools are read-only. A timeseries takes `from` and `to`."
          bullets << "- `start` and `start_at` are the same as `from`. `end` and `end_at` are the same as `to`."
          bullets << "- Pass metric filters as a `filters` object."
        end
        return if bullets.empty?

        ["## Metrics", *bullets].join("\n")
      end

      def endpoint_tools(surface)
        return unless surface.endpoints_enabled?

        <<~MD.strip
          ## Endpoint tools

          - One tool per named route. Path tokens are tool arguments.
          - If a tool returns a list and another returns detail, fetch the detail before you build a screen.
        MD
      end

      def live_updates
        return unless RecordingStudioMcp.events_registered?

        <<~MD.strip
          ## Live updates

          - List and read accessible items as resources.
          - Subscribe to a resource URI to hear when that item changes, then read it again.
        MD
      end

      def skills
        <<~MD.strip
          ## Skills

          - This server may list skills with extra guidance for these tools.
        MD
      end

      private_class_method :intro, :authentication, :records_and_parents, :listing_and_pagination,
                           :metrics, :endpoint_tools, :live_updates, :skills
    end
  end
end
