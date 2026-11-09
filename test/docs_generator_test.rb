# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_mcp/mcp_docs/mcp_docs_generator"

class DocsGeneratorTest < Minitest::Test
  def with_temp_app
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
      yield dir
    end
  end

  def build_generator(destination_root, args = ["public_api"], options = {})
    RecordingStudioMcp::Generators::McpDocsGenerator.new(
      args,
      options,
      destination_root: destination_root
    )
  end

  def test_installs_route_helper_and_initializer
    with_temp_app do |destination_root|
      generator = build_generator(
        destination_root,
        ["public_api"],
        mount_path: "/admin/public-api/mcp-docs",
        layout: "recording_studio/default_layout"
      )
      generator.invoke_all

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      initializer_path = File.join(destination_root, "config/initializers/recording_studio_mcp_docs_public_api.rb")
      initializer = File.read(initializer_path)

      assert_includes routes, "recording_studio_mcp_docs_for :public"
      assert_includes routes, 'at: "/admin/public-api/mcp-docs"'
      assert_includes routes, "as: :public_api_mcp_docs"
      assert_includes initializer, "config.documentation_enabled = true"
      assert_includes initializer, "config.documentation_access = :authenticated"
      assert_includes initializer, 'config.documentation_layout_name = "recording_studio/default_layout"'
    end
  end

  def test_operations_surface_uses_named_api
    with_temp_app do |destination_root|
      generator = build_generator(
        destination_root,
        ["operations_api"],
        mount_path: "/admin/operations-api/mcp-docs",
        api_surface: "operations"
      )
      generator.invoke_all

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      assert_includes routes, "recording_studio_mcp_docs_for :operations"
      assert_includes routes, "as: :operations_api_mcp_docs"
    end
  end
end
