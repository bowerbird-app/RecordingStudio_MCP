# frozen_string_literal: true

require "test_helper"
require_relative "mcp_ui_support"

class McpUiTest < Minitest::Test
  FakeGrant = Struct.new(:api_client, :credential, :access_recording, :root_recording, :accessible_recordings,
                         keyword_init: true)
  FakeClient = Struct.new(:api_key)

  def setup
    McpUiSupport.install_fake_mcp_ui
    RecordingStudio::MCP_UI.reset!
    @grant = FakeGrant.new(api_client: FakeClient.new("public"), accessible_recordings: [])
  end

  def teardown
    McpUiSupport.remove_fake_mcp_ui
    super
  end

  def test_endpoint_tool_meta_is_present_only_when_ui_and_widget_exist
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        "presskits.edit",
        http_verb: :patch,
        path: "presskits/:id",
        handler: ->(_context) { { id: "1" } },
        ui: "presskits.editor"
      )
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )

      tools = RecordingStudioMcp::Tools.definitions
      ping = tools.find { |tool| tool[:name] == "ping" }
      refute ping.key?(:_meta)

      edit = tools.find { |tool| tool[:name] == "presskits.edit" }
      refute edit.key?(:_meta)

      RecordingStudio::MCP_UI.register("presskits.editor", actions: { save: "presskits.update" })
      tools = RecordingStudioMcp::Tools.definitions
      edit = tools.find { |tool| tool[:name] == "presskits.edit" }
      assert_equal "ui://presskits/editor", edit.dig(:_meta, :ui, :resourceUri)
      ping = tools.find { |tool| tool[:name] == "ping" }
      refute ping.key?(:_meta)
    end
  end

  def test_resources_read_packages_html_and_hides_unauthorized
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        "presskits.edit",
        http_verb: :patch,
        path: "presskits/:id",
        handler: ->(_context) { { id: "1" } },
        ui: "presskits.editor"
      )
      RecordingStudio::MCP_UI.register("presskits.editor", actions: { save: "presskits.update" })

      listed = RecordingStudioMcp::Resources.list(access_grant: @grant)
      assert_equal "ui://presskits/editor", listed.payload[:resources].first[:uri]
      assert_equal "text/html;profile=mcp-app", listed.payload[:resources].first[:mimeType]

      read = RecordingStudioMcp::Resources.read(access_grant: @grant, uri: "ui://presskits/editor")
      content = read.payload[:contents].first
      assert_equal "text/html;profile=mcp-app", content[:mimeType]
      assert_includes content[:text], "presskits.editor"
      assert content.dig(:_meta, :ui, :csp)

      RecordingStudio::MCP_UI.hidden << "presskits.editor"
      hidden = RecordingStudioMcp::Resources.read(access_grant: @grant, uri: "ui://presskits/editor")
      assert_instance_of RecordingStudioMcp::Resources::NotFound, hidden
      refute RecordingStudioMcp::Resources.accessible?(@grant, "ui://presskits/editor")
      listed = RecordingStudioMcp::Resources.list(access_grant: @grant)
      refute(listed.payload[:resources].any? { |entry| entry[:uri].to_s.start_with?("ui://") })
    end
  end

  def test_widget_dispatch_maps_alias_rejects_unknown_and_unauthorized
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        "presskits.update",
        http_verb: :patch,
        path: "presskits/:id",
        handler: ->(context) { { id: context.params[:id], title: context.params[:title] } },
        ui: "presskits.editor"
      )
      RecordingStudio::MCP_UI.register("presskits.editor", actions: { save: "presskits.update" })

      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "save",
        arguments: { id: "kit-1", title: "Studio" },
        access_grant: @grant,
        meta: { "ui" => { "resourceUri" => "ui://presskits/editor" } }
      )
      refute result[:isError]
      assert_equal true, result.dig(:structuredContent, "ok")
      assert_equal "Studio", result.dig(:structuredContent, "data", "title")
      assert_equal({}, result.dig(:structuredContent, "errors"))
      assert_equal "Studio", result.dig(:structuredContent, "contextUpdate", "title")

      unknown = RecordingStudioMcp::Dispatcher.call(
        tool_name: "delete",
        arguments: { id: "kit-1" },
        access_grant: @grant,
        meta: { "ui" => { "resourceUri" => "ui://presskits/editor" } }
      )
      assert unknown[:isError]
      assert_equal false, unknown.dig(:structuredContent, "ok")
      assert unknown.dig(:structuredContent, "errors", "alias")

      invalid = RecordingStudioMcp::Dispatcher.call(
        tool_name: "save",
        arguments: { id: "kit-1" },
        access_grant: @grant,
        meta: { "ui" => { "resourceUri" => "ui://presskits/editor" } }
      )
      assert invalid[:isError]
      assert_equal false, invalid.dig(:structuredContent, "ok")
      assert invalid.dig(:structuredContent, "errors", "base")

      RecordingStudio::MCP_UI.hidden << "presskits.editor"
      denied = RecordingStudioMcp::Dispatcher.call(
        tool_name: "save",
        arguments: { id: "kit-1", title: "Studio" },
        access_grant: @grant,
        meta: { "ui" => { "resourceUri" => "ui://presskits/editor" } }
      )
      assert denied[:isError]
      assert_includes denied.dig(:structuredContent, "errors", "base").first, "not available"
    end
  end

  def test_without_mcp_ui_tools_and_resources_stay_unchanged
    McpUiSupport.remove_fake_mcp_ui
    refute RecordingStudioMcp::McpUi.loaded?

    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        "presskits.edit",
        http_verb: :patch,
        path: "presskits/:id",
        handler: ->(_context) { { id: "1" } },
        ui: "presskits.editor"
      )

      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "presskits.edit" }
      refute tool.key?(:_meta)

      listed = RecordingStudioMcp::Resources.list(access_grant: @grant)
      refute(listed.payload[:resources].any? { |entry| entry[:uri].to_s.start_with?("ui://") })

      answer = RecordingStudioMcp::Resources.read(access_grant: @grant, uri: "ui://presskits/editor")
      assert_instance_of RecordingStudioMcp::Resources::InvalidParams, answer

      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "save",
        arguments: { id: "kit-1" },
        access_grant: @grant,
        meta: { "ui" => { "resourceUri" => "ui://presskits/editor" } }
      )
      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool save"
      refute result.key?(:structuredContent)
    end
  end

  def test_install_host_hooks_sets_empty_slots
    RecordingStudioMcp::McpUi.install_host_hooks
    assert RecordingStudio::MCP_UI.configuration.visibility_checker
    assert RecordingStudio::MCP_UI.configuration.action_executor

    custom = ->(*) { false }
    RecordingStudio::MCP_UI.configuration.visibility_checker = custom
    RecordingStudioMcp::McpUi.install_host_hooks
    assert_same custom, RecordingStudio::MCP_UI.configuration.visibility_checker
  end
end
