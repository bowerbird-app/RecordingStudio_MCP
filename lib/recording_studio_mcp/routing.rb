# frozen_string_literal: true

require "action_dispatch/routing/mapper"

module RecordingStudioMcp
  module Routing
    def recording_studio_mcp_docs_for(api_name, at:, as:)
      api_key = api_name.to_s
      mount_path = at.to_s.sub(%r{/+\z}, "")
      route_key = as.to_s
      defaults = { api_key: api_key }

      get mount_path,
          to: "recording_studio_mcp/mcp_docs#show",
          defaults: defaults,
          as: route_key
    end
  end
end

ActionDispatch::Routing::Mapper.include(RecordingStudioMcp::Routing)
