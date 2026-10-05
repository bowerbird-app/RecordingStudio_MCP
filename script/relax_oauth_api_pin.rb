# frozen_string_literal: true

# Oauth gemspecs through v0.5.4 still declare recording_studio_api ~> 0.5.2
# (>= 0.5.2, < 0.6). MCP needs API 0.6. Bundler 4 resolves git gems from
# Gem::StubSpecification, not Bundler.load_gemspec.
require "bundler/source/git"
require "bundler/source/path"

module RelaxOauthApiPin
  API_REQ = Gem::Requirement.new(">= 0.5.2", "< 0.7").freeze

  def load_gemspec(file)
    relax(super)
  end

  private

  def relax(spec)
    return spec unless spec&.name == "recording_studio_oauth"

    spec.dependencies.each do |dep|
      next unless dep.name == "recording_studio_api"

      dep.instance_variable_set(:@requirement, API_REQ.dup)
    end
    spec
  end
end

Bundler::Source::Git.prepend(RelaxOauthApiPin)
Bundler::Source::Path.prepend(RelaxOauthApiPin)
