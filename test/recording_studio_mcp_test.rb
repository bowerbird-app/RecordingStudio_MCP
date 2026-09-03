# frozen_string_literal: true

require "json"
require "test_helper"

class RecordingStudioMcpTest < Minitest::Test
  def test_version_is_0_1_0
    assert_equal "0.1.0", ::RecordingStudioMcp::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudioMcp::Engine
  end

  def test_gemspec_pins_live_addons
    gemspec = File.read(File.expand_path("../recording_studio_mcp.gemspec", __dir__))

    assert_includes gemspec, 'spec.add_dependency "recording_studio", "~> 4.2"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_api", "~> 0.5.2"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_oauth", "~> 0.1"'
    refute_includes gemspec, "recording_studio_users"
    refute_includes gemspec, "doorkeeper"
    refute_includes gemspec, "omniauth"
    refute_includes gemspec, "recording_studio_site_settings"
    refute_includes gemspec, "flat_pack"
  end

  def test_gemspec_excludes_cursor_config
    spec = Gem::Specification.load(File.expand_path("../recording_studio_mcp.gemspec", __dir__))
    cursor_files = spec.files.select { |path| path == ".cursor" || path.split("/").include?(".cursor") }

    assert_empty cursor_files, "gemspec must not package .cursor/ (got #{cursor_files.inspect})"
  end

  def test_homepage_is_this_repo
    gemspec = File.read(File.expand_path("../recording_studio_mcp.gemspec", __dir__))

    assert_includes gemspec, "https://github.com/bowerbird-app/RecordingStudio_MCP"
    refute_includes gemspec, "RecordingStudio_gem_template"
    refute_includes gemspec, "gem_template"
  end

  def test_cursor_environment_is_repo_managed_without_snapshot
    path = File.expand_path("../.cursor/environment.json", __dir__)
    json = JSON.parse(File.read(path))

    assert_equal "Recording Studio MCP", json["name"]
    assert_equal ".cursor/install.sh", json["install"]
    assert_equal ".cursor/start.sh", json["start"]
    refute json.key?("snapshot")
  end

  def test_cursor_install_fetches_skills_last_without_or_true
    install_script = File.read(File.expand_path("../.cursor/install.sh", __dir__))

    assert_includes install_script, "fetch-skills.sh"
    refute_includes install_script, 'fetch-skills.sh" || true'
    fetch_at = install_script.rindex(%r{"\$\{SCRIPT_DIR\}/fetch-skills\.sh"})
    complete_at = install_script.rindex("install.sh complete")
    assert_operator fetch_at, :<, complete_at
  end

  def test_dummy_gemfile_pins_live_github_tags
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v4.2.1"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.9.1"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_admin", tag: "v2.0.2"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_api", tag: "v0.5.2"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_Oauth", tag: "v0.1.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_attachable", tag: "v0.5.1"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_site_settings", tag: "v0.1.0"'
    assert_includes gemfile, 'github: "bowerbird-app/flatpack", tag: "v0.1.144"'
    refute_includes gemfile, "recording_studio_users"
    refute_includes gemfile, 'tag: "v0.6.0"'
  end

  def test_does_not_ship_example_mixin_or_copied_core
    refute File.exist?(File.expand_path("../lib/recording_studio_mcp/capabilities/example.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_mcp/hooks.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_mcp/services/base_service.rb", __dir__))
  end

  def test_product_readme_is_not_the_template
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "Recording Studio MCP"
    assert_includes readme, "Streamable HTTP"
    assert_includes readme, "WWW-Authenticate"
    refute_includes readme, "Internal template"
    refute_includes readme, "GemTemplate"
    refute_includes readme, "v3 declarations"
  end

  def test_engine_does_not_ship_product_views
    erb_views = Dir[File.expand_path("../app/views/recording_studio_mcp/**/*.erb", __dir__)]

    assert_empty erb_views
  end

  def test_dummy_home_is_dummy_only
    view_source = File.read(File.expand_path("dummy/app/views/home/index.html.erb", __dir__))

    assert_includes view_source, "/recording_studio_mcp"
    refute_includes view_source, "Template Demo"
    refute_includes view_source, "bin/rename_gem"
  end
end
