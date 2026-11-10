# frozen_string_literal: true

require "action_dispatch/routing/mapper"
require_relative "redoc"

module RecordingStudioMcp
  module Routing
    def recording_studio_mcp_docs_for(api_name, at:, as:)
      mount_path = at.to_s.sub(%r{/+\z}, "")
      defaults = { api_key: api_name.to_s }
      draw_docs_spec_route(mount_path, defaults, as.to_s)
      draw_docs_asset_routes(mount_path, defaults)
      draw_docs_page_route(mount_path, defaults, as.to_s)
    end

    private

    def draw_docs_spec_route(mount_path, defaults, route_key)
      get "#{mount_path}/openapi.json",
          to: "recording_studio_mcp/mcp_docs#openapi",
          defaults: defaults,
          as: :"#{route_key}_openapi"
    end

    def draw_docs_asset_routes(mount_path, defaults)
      Redoc::FILES.each_key do |asset|
        get "#{mount_path}/#{asset}",
            to: "recording_studio_mcp/mcp_docs#asset",
            defaults: defaults.merge(asset: asset),
            format: false
      end
    end

    def draw_docs_page_route(mount_path, defaults, route_key)
      get mount_path,
          to: "recording_studio_mcp/mcp_docs#show",
          defaults: defaults,
          as: route_key
    end
  end
end

ActionDispatch::Routing::Mapper.include(RecordingStudioMcp::Routing)
