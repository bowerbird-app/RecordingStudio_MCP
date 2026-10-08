# frozen_string_literal: true

require "test_helper"

class ToolsTest < Minitest::Test
  def test_tree_names_are_the_parameterized_set
    assert_equal %w[list show create update delete capability_action describe], RecordingStudioMcp::Tools::TREE_NAMES
  end

  def test_definitions_with_types_include_tree_tools
    with_isolated_api_configuration do
      register_tree_type("Page")
      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[list show create update capability_action describe], names
    end
  end

  def test_definitions_with_empty_types_and_endpoints_are_endpoint_tools_only
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :zeta,
        http_verb: :get,
        path: "zeta",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :alpha,
        http_verb: :post,
        path: "alpha/:name",
        handler: ->(_context) { { ok: true } }
      )

      tools = RecordingStudioMcp::Tools.definitions
      names = tools.map { |tool| tool[:name] }

      assert_equal %w[alpha zeta], names
      refute_includes names, "list"
      refute_includes names, "describe"
    end
  end

  def test_mixed_definitions_put_tree_tools_before_sorted_endpoints
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioApi.register_endpoint(
        :zeta,
        http_verb: :get,
        path: "zeta",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioApi.register_endpoint(
        :alpha,
        http_verb: :get,
        path: "alpha",
        handler: ->(_context) { { ok: true } }
      )

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[list show create update capability_action describe] + %w[alpha zeta], names
    end
  end

  def test_list_requires_type
    with_isolated_api_configuration do
      register_tree_type("Page")
      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "list" }.fetch(:inputSchema)

      assert_equal ["type"], schema.fetch(:required)
      assert schema.fetch(:properties).key?(:pagination_token)
    end
  end

  def test_tools_have_display_titles
    expected = {
      "list" => "List records",
      "show" => "Show a record",
      "create" => "Create a record",
      "update" => "Update a record",
      "capability_action" => "Run a capability action",
      "describe" => "Describe a type"
    }

    with_isolated_api_configuration do
      register_tree_type("Page")
      expected.each do |name, title|
        tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
        assert_equal title, tool[:title], name
      end
    end
  end

  def test_read_tools_are_marked_read_only
    with_isolated_api_configuration do
      register_tree_type("Page")
      %w[list show describe].each do |name|
        tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == name }
        assert_equal true, tool.dig(:annotations, :readOnlyHint), name
        assert_equal false, tool.dig(:annotations, :destructiveHint), name
        assert_equal true, tool.dig(:annotations, :idempotentHint), name
        assert_equal false, tool.dig(:annotations, :openWorldHint), name
      end
    end
  end

  def test_write_tools_are_marked_as_changing_data
    with_isolated_api_configuration do
      register_tree_type("Page")
      create = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "create" }
      update = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "update" }
      action = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "capability_action" }

      [create, update].each do |tool|
        assert_equal false, tool.dig(:annotations, :readOnlyHint), tool[:name]
        assert_equal false, tool.dig(:annotations, :destructiveHint), tool[:name]
        assert_equal false, tool.dig(:annotations, :openWorldHint), tool[:name]
        assert_includes tool[:description], "Changes data"
      end

      assert_equal true, create.dig(:annotations, :idempotentHint)
      assert_equal false, update.dig(:annotations, :idempotentHint)

      assert_equal false, action.dig(:annotations, :readOnlyHint)
      assert_equal true, action.dig(:annotations, :destructiveHint)
      assert_equal false, action.dig(:annotations, :idempotentHint)
      assert_equal false, action.dig(:annotations, :openWorldHint)
      assert_includes action[:description], "destructively change data"
    end
  end

  def test_delete_is_listed_only_when_a_type_supports_destroy
    with_isolated_api_configuration do
      register_tree_type("Page")
      refute_includes RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }, "delete"

      register_tree_type("SupportPage", operations: %i[index show create update destroy])
      tools = RecordingStudioMcp::Tools.definitions
      delete = tools.find { |tool| tool[:name] == "delete" }

      assert delete
      assert_equal "Delete a record", delete[:title]
      assert_equal false, delete.dig(:annotations, :readOnlyHint)
      assert_equal true, delete.dig(:annotations, :destructiveHint)
      assert_equal false, delete.dig(:annotations, :idempotentHint)
      assert_includes delete[:description], "destructively change data"
      assert_equal ["SupportPage"], delete.dig(:inputSchema, :properties, :type, :enum)
    end
  end

  def test_create_has_no_attributes_envelope
    with_isolated_api_configuration do
      register_tree_type("Page")
      schema = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "create" }.fetch(:inputSchema)

      refute schema.fetch(:properties).key?(:attributes)
      assert_equal true, schema[:additionalProperties]
    end
  end

  def test_endpoint_tool_uses_openapi_and_verb_annotations
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :flatpack_component,
      http_verb: :get,
      path: "flatpack/components/:name",
      handler: ->(_context) { {} },
      openapi: { summary: "Show a component", description: "Return one Flatpack component." }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal "flatpack_component", tool[:name]
    assert_equal "Show a component", tool[:title]
    assert_includes tool[:description], "Return one Flatpack component."
    assert_includes tool[:description], "GET flatpack/components/:name"
    assert_equal true, tool.dig(:annotations, :readOnlyHint)
    assert_equal true, tool.dig(:annotations, :idempotentHint)
    assert_equal false, tool.dig(:annotations, :destructiveHint)
    assert_equal ["name"], tool.dig(:inputSchema, :required)
  end

  def test_endpoint_contract_closes_additional_properties
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :shout,
      http_verb: :post,
      path: "shout",
      handler: ->(_context) { {} },
      input_contract: {
        fields: {
          message: { type: :string, required: true }
        }
      }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal false, tool.dig(:inputSchema, :additionalProperties)
    assert_equal false, tool.dig(:annotations, :readOnlyHint)
  end

  def test_delete_endpoint_is_marked_destructive
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :remove_widget,
      http_verb: :delete,
      path: "widgets/:id",
      handler: ->(_context) { {} }
    )

    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint)

    assert_equal false, tool.dig(:annotations, :readOnlyHint)
    assert_equal true, tool.dig(:annotations, :destructiveHint)
    assert_equal false, tool.dig(:annotations, :idempotentHint)
  end
end
