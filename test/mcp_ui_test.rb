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

      RecordingStudio::MCP_UI.register("presskits.editor")
      tools = RecordingStudioMcp::Tools.definitions
      edit = tools.find { |tool| tool[:name] == "presskits.edit" }
      assert_equal "ui://presskits/editor", edit.dig(:_meta, :ui, :resourceUri)
      ping = tools.find { |tool| tool[:name] == "ping" }
      refute ping.key?(:_meta)
    end
  end

  def test_resources_list_and_read_ui_and_hide_unauthorized
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        "presskits.edit",
        http_verb: :patch,
        path: "presskits/:id",
        handler: ->(_context) { { id: "1" } },
        ui: "presskits.editor"
      )
      RecordingStudio::MCP_UI.register("presskits.editor")
      RecordingStudio::MCP_UI.register("secret.editor")

      listed = RecordingStudioMcp::Resources.list(access_grant: @grant)
      uris = listed.payload[:resources].map { |entry| entry[:uri] }
      assert_equal ["ui://presskits/editor"], uris
      assert_equal "text/html;profile=mcp-app", listed.payload[:resources].first[:mimeType]

      read = RecordingStudioMcp::Resources.read(access_grant: @grant, uri: "ui://presskits/editor")
      content = read.payload[:contents].first
      assert_equal "text/html;profile=mcp-app", content[:mimeType]
      assert_includes content[:text], "presskits.editor"
      assert content.dig(:_meta, :ui, :csp)

      hidden = RecordingStudioMcp::Resources.read(access_grant: @grant, uri: "ui://secret/editor")
      assert_instance_of RecordingStudioMcp::Resources::NotFound, hidden
      refute RecordingStudioMcp::Resources.accessible?(@grant, "ui://secret/editor")
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
    end
  end

  def test_normal_tools_call_is_unchanged
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } },
        ui: "status.ping"
      )
      RecordingStudio::MCP_UI.register("status.ping")

      answer = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => { "name" => "ping", "arguments" => {} }
        },
        access_grant: @grant
      )
      result = answer.body.fetch(:result)
      refute result[:isError]
      assert_equal true, result.dig(:structuredContent, "ok")
    end
  end
end
