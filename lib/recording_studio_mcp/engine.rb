# frozen_string_literal: true

require "recording_studio"
require "recording_studio_api"
require "recording_studio_oauth"

module RecordingStudioMcp
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioMcp

    initializer "recording_studio_mcp.load_config" do |app|
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:recording_studio_mcp)
          rescue StandardError
            nil
          end
          RecordingStudioMcp.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError
          nil
        end
      end

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_mcp)
        xcfg = app.config.x.recording_studio_mcp
        if xcfg.respond_to?(:to_h)
          RecordingStudioMcp.configuration.merge!(xcfg.to_h)
        elsif xcfg.respond_to?(:each_pair)
          hash = {}
          xcfg.each_pair { |key, value| hash[key] = value }
          RecordingStudioMcp.configuration.merge!(hash) if hash.any?
        end
      end
    end
  end
end
