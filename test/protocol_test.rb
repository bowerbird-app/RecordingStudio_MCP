# frozen_string_literal: true

require "test_helper"

class ProtocolTest < Minitest::Test
  FakeGrant = Struct.new(:api_client)

  def setup
    @grant = FakeGrant.new(nil)
  end

  def test_initialize_returns_tree_instructions_when_types_exist
    with_isolated_api_configuration do
      register_tree_type("Page")
      result = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => { "protocolVersion" => "2025-06-18", "capabilities" => {}, "clientInfo" => { "name" => "test" } }
        },
        access_grant: @grant
      )

      instructions = result.body.dig(:result, :instructions)
      assert_equal :ok, result.status
      assert_equal "2025-06-18", result.body.dig(:result, :protocolVersion)
      assert_equal false, result.body.dig(:result, :capabilities, :tools, :listChanged)
      assert_equal "recording-studio", result.body.dig(:result, :serverInfo, :name)
      assert_equal RecordingStudioMcp::VERSION, result.body.dig(:result, :serverInfo, :version)
      assert_includes instructions, "Call describe before create"
      assert_includes instructions, "meta.next_pagination_token"
      assert_includes instructions, "both this MCP endpoint and the Recording Studio API"
      refute_includes instructions, "Use the endpoint tools"
    end
  end

  def test_initialize_returns_catalog_only_instructions
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      result = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => { "protocolVersion" => "2025-06-18", "capabilities" => {}, "clientInfo" => { "name" => "test" } }
        },
        access_grant: @grant
      )

      instructions = result.body.dig(:result, :instructions)
      assert_includes instructions, "both this MCP endpoint and the Recording Studio API"
      assert_includes instructions, "Use the endpoint tools"
      assert_includes instructions, "Path parameters are tool arguments"
      assert_includes instructions, "Call tools/list to see the available endpoint tools"
      assert_includes instructions, "fetch the detail before generating UI"
      assert_includes instructions, "call tools/list again"
      refute_includes instructions, "Call describe before create"
    end
  end

  def test_tools_list_returns_tree_tools_when_types_exist
    with_isolated_api_configuration do
      register_tree_type("Page")
      result = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
        access_grant: @grant
      )

      names = result.body.dig(:result, :tools).map { |tool| tool[:name] }
      assert_equal %w[list show create update capability_action describe], names
    end
  end

  def test_tools_list_returns_endpoint_tools_on_catalog_only_host
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      result = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
        access_grant: @grant
      )

      names = result.body.dig(:result, :tools).map { |tool| tool[:name] }
      assert_equal %w[ping], names
    end
  end

  def test_unknown_method_is_method_not_found
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 3, "method" => "nope" },
      access_grant: @grant
    )

    assert_equal(-32_601, result.body.dig(:error, :code))
  end

  def test_parse_error
    result = RecordingStudioMcp::Protocol.handle("{", access_grant: @grant)

    assert_equal(-32_700, result.body.dig(:error, :code))
  end

  def test_initialized_notification_has_no_body
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "method" => "notifications/initialized" },
      access_grant: @grant
    )

    assert result.notification
    assert_nil result.body
  end

  def test_ping_returns_empty_result
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 4, "method" => "ping" },
      access_grant: @grant
    )

    assert_equal({}, result.body[:result])
  end

  def test_invalid_request_without_jsonrpc
    result = RecordingStudioMcp::Protocol.handle(
      { "id" => 5, "method" => "ping" },
      access_grant: @grant
    )

    assert_equal(-32_600, result.body.dig(:error, :code))
  end

  def test_initialize_falls_back_to_default_protocol_version
    result = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "initialize",
        "params" => { "protocolVersion" => "1999-01-01" }
      },
      access_grant: @grant
    )

    assert_equal "2025-06-18", result.body.dig(:result, :protocolVersion)
  end

  def test_initialize_accepts_2026_07_28
    result = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "initialize",
        "params" => { "protocolVersion" => "2026-07-28" }
      },
      access_grant: @grant
    )

    assert_equal "2026-07-28", result.body.dig(:result, :protocolVersion)
    assert_nil result.session_id
  end

  def test_server_discover_lists_supported_versions
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 10, "method" => "server/discover" },
      access_grant: @grant
    )

    assert_equal(
      %w[2025-03-26 2025-06-18 2026-07-28],
      result.body.dig(:result, :protocolVersions)
    )
  end

  def test_legacy_subscribe_requires_a_registered_event_and_session
    with_isolated_mcp_configuration do
      missing = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 11, "method" => "resources/subscribe", "params" => { "uri" => "recording://1" } },
        access_grant: @grant
      )
      assert_equal(-32_601, missing.body.dig(:error, :code))

      RecordingStudioMcp.register_event("recording updated")
      grant = Object.new
      grant.define_singleton_method(:accessible_recordings) do
        Object.new.tap do |scope|
          scope.define_singleton_method(:find_by) { |*| Object.new }
        end
      end
      context = RecordingStudioMcp::RequestContext.new(
        request_id: 12,
        protocol_version: "2025-06-18",
        access_grant: grant
      )
      no_session = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 12, "method" => "resources/subscribe", "params" => { "uri" => "recording://1" } },
        access_grant: grant,
        request_context: context
      )
      assert_equal(-32_602, no_session.body.dig(:error, :code))
      assert_equal "No listening session", no_session.body.dig(:error, :message)
    end
  end

  def test_modern_listen_opens_a_stream_for_accessible_uris
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = Object.new
      grant.define_singleton_method(:accessible_recordings) do
        Object.new.tap do |scope|
          scope.define_singleton_method(:find_by) { |id:| id.to_s == "5" ? Object.new : nil }
        end
      end
      context = RecordingStudioMcp::RequestContext.new(
        request_id: 13,
        protocol_version: "2026-07-28",
        access_grant: grant
      )
      result = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 13,
          "method" => "subscriptions/listen",
          "params" => { "notifications" => { "resourceSubscriptions" => %w[recording://5 recording://9] } }
        },
        access_grant: grant,
        request_context: context
      )

      assert result.listen
      assert_equal ["recording://5"], result.listen_connection.subscribed_uris
      assert_equal 13, result.listen_connection.subscription_id
    end
  end

  def test_legacy_initialize_opens_a_session_when_context_is_present
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 15,
      protocol_version: "2025-06-18",
      access_grant: @grant
    )
    result = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 15,
        "method" => "initialize",
        "params" => { "protocolVersion" => "2025-06-18" }
      },
      access_grant: @grant,
      request_context: context
    )

    assert result.session_id.present?
    assert_same context.connection, RecordingStudioMcp::Connections.fetch(result.session_id)
  end

  def test_resources_list_read_subscribe_and_unsubscribe
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      recording = Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)
                        .new(8, "Page", Struct.new(:title).new("Listed"), nil, 1)
      scope = Object.new
      scope.define_singleton_method(:includes) { |_| scope }
      scope.define_singleton_method(:order) { |_| [recording] }
      scope.define_singleton_method(:find_by) { |id:| recording if id.to_s == "8" }
      grant = Object.new
      grant.define_singleton_method(:accessible_recordings) { scope }
      grant.define_singleton_method(:api_client) { nil }

      listed = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 16, "method" => "resources/list" },
        access_grant: grant
      )
      assert_equal "recording://8", listed.body.dig(:result, :resources, 0, :uri)

      bad_list = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 17, "method" => "resources/list", "params" => { "cursor" => "x" } },
        access_grant: grant
      )
      assert_equal(-32_602, bad_list.body.dig(:error, :code))

      read = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 18, "method" => "resources/read", "params" => { "uri" => "recording://8" } },
        access_grant: grant
      )
      assert_includes read.body.dig(:result, :contents, 0, :text), "Listed"

      missing = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 19, "method" => "resources/read", "params" => { "uri" => "recording://404" } },
        access_grant: grant
      )
      assert_equal(-32_002, missing.body.dig(:error, :code))

      invalid = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 20, "method" => "resources/read", "params" => { "uri" => "nope" } },
        access_grant: grant
      )
      assert_equal(-32_602, invalid.body.dig(:error, :code))

      context = RecordingStudioMcp::RequestContext.new(
        request_id: 21,
        protocol_version: "2025-06-18",
        access_grant: grant
      )
      opened = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      context.attach_connection(opened)

      subscribed = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 21, "method" => "resources/subscribe", "params" => { "uri" => "recording://8" } },
        access_grant: grant,
        request_context: context
      )
      assert_equal({}, subscribed.body[:result])
      assert opened.subscribed?("recording://8")

      unsubscribed = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 22, "method" => "resources/unsubscribe",
          "params" => { "uri" => "recording://8" } },
        access_grant: grant,
        request_context: context
      )
      assert_equal({}, unsubscribed.body[:result])
      refute opened.subscribed?("recording://8")
    end
  end

  def test_listen_and_unsubscribe_are_hidden_until_events_are_registered
    with_isolated_mcp_configuration do
      context = RecordingStudioMcp::RequestContext.new(
        request_id: 23,
        protocol_version: "2026-07-28",
        access_grant: @grant
      )
      listen = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 23, "method" => "subscriptions/listen" },
        access_grant: @grant,
        request_context: context
      )
      assert_equal(-32_601, listen.body.dig(:error, :code))

      RecordingStudioMcp.register_event("recording updated")
      legacy = RecordingStudioMcp::RequestContext.new(
        request_id: 24,
        protocol_version: "2025-06-18",
        access_grant: @grant
      )
      listen_legacy = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 24, "method" => "subscriptions/listen" },
        access_grant: @grant,
        request_context: legacy
      )
      assert_equal(-32_601, listen_legacy.body.dig(:error, :code))

      no_session = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 25, "method" => "resources/unsubscribe",
          "params" => { "uri" => "recording://1" } },
        access_grant: @grant,
        request_context: legacy
      )
      assert_equal(-32_602, no_session.body.dig(:error, :code))
    end
  end

  def test_modern_clients_do_not_get_resources_subscribe
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      context = RecordingStudioMcp::RequestContext.new(
        request_id: 14,
        protocol_version: "2026-07-28",
        access_grant: @grant
      )
      result = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 14, "method" => "resources/subscribe", "params" => { "uri" => "recording://1" } },
        access_grant: @grant,
        request_context: context
      )

      assert_equal(-32_601, result.body.dig(:error, :code))
    end
  end

  def test_tools_call_passes_idempotency_key
    captured = nil
    RecordingStudioMcp::Dispatcher.stub(:call, lambda { |**kwargs|
      captured = kwargs
      { content: [{ type: "text", text: "{}" }], structuredContent: {}, isError: false }
    }) do
      RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 8,
          "method" => "tools/call",
          "params" => { "name" => "create", "arguments" => { "type" => "Page", "title" => "Hi" } }
        },
        access_grant: @grant,
        idempotency_key: "create-1"
      )
    end

    assert_equal "create-1", captured[:idempotency_key]
  end

  def test_tools_call_passes_request_context
    captured = nil
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 8,
      protocol_version: "2025-06-18",
      access_grant: @grant,
      progress_token: "tok"
    )
    RecordingStudioMcp::Dispatcher.stub(:call, lambda { |**kwargs|
      captured = kwargs
      { content: [{ type: "text", text: "{}" }], structuredContent: {}, isError: false }
    }) do
      RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 8,
          "method" => "tools/call",
          "params" => { "name" => "list", "arguments" => { "type" => "Page" } }
        },
        access_grant: @grant,
        request_context: context
      )
    end

    assert_same context, captured[:request_context]
  end

  def test_tools_call_dispatches
    stub_result = {
      content: [{ type: "text", text: "{}" }],
      structuredContent: {},
      isError: false
    }
    RecordingStudioMcp::Dispatcher.stub(:call, stub_result) do
      result = RecordingStudioMcp::Protocol.handle(
        {
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "tools/call",
          "params" => { "name" => "list", "arguments" => { "type" => "Workspace" } }
        },
        access_grant: @grant
      )

      refute result.body.dig(:result, :isError)
    end
  end
end
