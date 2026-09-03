# frozen_string_literal: true

require_relative "lib/recording_studio_mcp/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_mcp"
  spec.version     = RecordingStudioMcp::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_MCP"
  spec.summary     = "Remote MCP HTTP endpoint for Recording Studio"
  spec.description = "Mountable engine that exposes Streamable HTTP MCP over Recording Studio API. " \
                     "Access is user-delegated OAuth. Authorization is Accessible."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_MCP"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_MCP/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.2"
  spec.add_dependency "recording_studio_api", "~> 0.5.2"
  spec.add_dependency "recording_studio_oauth", "~> 0.1"
end
