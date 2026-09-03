# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_mcp/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  INSTALL_TEMPLATE_PATH = File.expand_path(
    "../lib/generators/recording_studio_mcp/install/templates/INSTALL.md",
    __dir__
  )

  def with_temp_app
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioMcp::Generators::InstallGenerator.new(
      [],
      options,
      destination_root: destination_root
    )
  end

  def test_mount_engine_uses_configured_mount_path
    generator = build_generator("/tmp", mount_path: "/addons/mcp")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ['mount RecordingStudioMcp::Engine, at: "/addons/mcp"'], routes
  end

  def test_default_mount_path_is_recording_studio_mcp
    generator = build_generator("/tmp")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ['mount RecordingStudioMcp::Engine, at: "/recording_studio_mcp"'], routes
  end

  def test_show_readme_displays_install_guide_for_invoke_behavior
    generator = build_generator("/tmp")
    shown_templates = []

    generator.stub(:behavior, :invoke) do
      generator.stub(:readme, ->(template) { shown_templates << template }) do
        generator.show_readme
      end
    end

    assert_equal ["INSTALL.md"], shown_templates
  end

  def test_install_guide_points_at_oauth_and_api
    install_guide = File.read(INSTALL_TEMPLATE_PATH)

    assert_includes install_guide, "Oauth"
    assert_includes install_guide, "oauth-protected-resource"
    refute_includes install_guide, "RecordingStudio v3"
    refute_includes install_guide, "FlatPack"
  end

  def test_generator_does_not_add_flatpack_tailwind
    source = File.read(File.expand_path("../lib/generators/recording_studio_mcp/install/install_generator.rb", __dir__))

    refute_includes source, "add_tailwind_source"
    refute_includes source, "flatpack"
  end
end
