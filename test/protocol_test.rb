# frozen_string_literal: true

require "test_helper"

class ProtocolTest < Minitest::Test
  FakeGrant = Struct.new(:api_client)

  def setup
    @grant = FakeGrant.new(nil)
  end

  def test_initialize_returns_server_info
    result = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => { "protocolVersion" => "2025-06-18", "capabilities" => {}, "clientInfo" => { "name" => "test" } }
      },
      access_grant: @grant
    )

    assert_equal :ok, result.status
    assert_equal "2025-06-18", result.body.dig(:result, :protocolVersion)
    assert_equal true, result.body.dig(:result, :capabilities, :tools, :listChanged)
    assert_equal "recording-studio", result.body.dig(:result, :serverInfo, :name)
    assert_equal RecordingStudioMcp::VERSION, result.body.dig(:result, :serverInfo, :version)
  end

  def test_tools_list_returns_parameterized_tools
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
      access_grant: @grant
    )

    names = result.body.dig(:result, :tools).map { |tool| tool[:name] }
    assert_equal %w[list show create update capability_action describe], names
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
