# frozen_string_literal: true

require "test_helper"

class RegistrationsTest < Minitest::Test
  def test_tools_list_is_opt_in_on_the_server
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :show }

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[show describe], names
    end
  end

  def test_describe_is_always_present
    with_isolated_api_configuration do
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools }

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal ["describe"], names
    end
  end

  def test_host_override_changes_title_only
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_tool(
        name: "list",
        operation: :index,
        title: "Find pages",
        description: "Host list copy.",
        input: {},
        output: "records"
      )

      list = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "list" }

      assert_equal "Find pages", list[:title]
    end
  end

  def test_override_cannot_change_target
    with_isolated_api_configuration do
      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.register_tool(
          name: "list",
          operation: :show,
          title: "List",
          description: "Wrong target.",
          input: {},
          output: "records"
        )
      end

      assert_includes error.message, "cannot change type or target"
    end
  end

  def test_unknown_field_on_a_typed_tool_raises
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :echo,
        http_verb: :post,
        path: "echo",
        handler: ->(_context) { { ok: true } },
        input_contract: { fields: { style: { type: :string, required: false } } }
      )
      RecordingStudioMcp.register_tool(
        name: "echo",
        endpoint: :echo,
        title: "Echo",
        description: "Echo a style.",
        input: { "not_a_field" => { description: "nope" } },
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :echo }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "not_a_field"
    end
  end

  def test_sensitive_tool_requires_allow_sensitive
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :secret_ping,
        http_verb: :get,
        path: "secret-ping",
        handler: ->(_context) { { ok: true } },
        sensitive: true
      )
      RecordingStudioMcp.register_tool(
        name: "secret_ping",
        endpoint: :secret_ping,
        title: "Secret ping",
        description: "A ping that is marked sensitive.",
        input: {},
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :secret_ping }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "allow_sensitive"
    end
  end

  def test_per_tool_allow_sensitive_includes_a_sensitive_item
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :secret_ping,
        http_verb: :get,
        path: "secret-ping",
        handler: ->(_context) { { ok: true } },
        sensitive: true
      )
      RecordingStudioMcp.register_tool(
        name: "secret_ping",
        endpoint: :secret_ping,
        title: "Secret ping",
        description: "A ping that is marked sensitive.",
        input: {},
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) do
        include_tool :secret_ping, allow_sensitive: true
      end

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_includes names, "secret_ping"
    end
  end

  def test_describe_is_lean_and_uses_register_type
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_type(type: "Page", description: "A page under a folder or workspace.")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      payload = catalog.describe("Page")

      assert_equal "A page under a folder or workspace.", payload["description"]
      assert_includes payload["tools"], "list"
      assert_equal [], payload["skills"]
      assert payload.key?("relationships")
      refute payload.key?("writable_fields")
      refute payload.key?("capability_actions")
    end
  end

  def test_dispatch_rejects_a_tool_not_on_the_server
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :show }
      grant = role_grant(:edit)
      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "list",
        arguments: { "type" => "Page" },
        access_grant: grant
      )

      assert_equal true, result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool list"
    end
  end

  def test_audit_lists_tools_and_sensitive_flags
    with_isolated_api_configuration do
      register_tree_type("Page")
      lines = RecordingStudioMcp.configuration.catalogs.audit!

      assert(lines.any? { |line| line.include?("server public") })
      assert(lines.any? { |line| line.include?("tool list sensitive=false") })
    end
  end
end
