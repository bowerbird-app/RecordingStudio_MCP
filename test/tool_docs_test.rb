# frozen_string_literal: true

require "test_helper"

class ToolDocsTest < Minitest::Test
  include IsolatedApiConfiguration

  def test_type_tags_use_the_registered_openapi_group
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api :public
      register_tree_type("Credit", openapi: { tag: { group: "Press kits" } })
      register_tree_type("Folder")

      docs = RecordingStudioMcp::ToolDocs

      assert_equal ["Press kits"], docs.type_tags("Credit", api: :public)
      assert_equal ["Types"], docs.type_tags("Folder", api: :public)
    end
  end

  def test_metric_group_tags_keep_common_acronyms_uppercase
    docs = RecordingStudioMcp::ToolDocs

    assert_equal "AI Runs", docs.humanize_metric_group("ai_runs")
    assert_equal "API Keys", docs.humanize_metric_group("api_keys")
    assert_equal "MCP Calls", docs.humanize_metric_group("mcp_calls")
    assert_equal ["AI Runs"], docs.metric_tags("ai_runs-total")
    assert_equal ["API Keys"], docs.metric_tags("api_keys-created_over_time")
    assert_equal ["MCP Calls"], docs.metric_tags("mcp_calls-over_time")
    assert_equal ["Folders"], docs.metric_tags("folders-total")
  end

  def test_endpoint_output_schema_skips_4xx_only
    schema = RecordingStudioMcp::ToolDocs.endpoint_output_schema(
      endpoint_with_responses("400" => json_object_schema(error: { type: "string" }))
    )

    assert_nil schema
  end

  def test_endpoint_output_schema_skips_default_only
    schema = RecordingStudioMcp::ToolDocs.endpoint_output_schema(
      endpoint_with_responses("default" => json_object_schema(error: { type: "string" }))
    )

    assert_nil schema
  end

  def test_endpoint_output_schema_skips_array_root
    schema = RecordingStudioMcp::ToolDocs.endpoint_output_schema(
      endpoint_with_responses(
        "200" => json_content({ type: "array", items: { type: "object" } })
      )
    )

    assert_nil schema
  end

  def test_endpoint_output_schema_skips_ref_only
    schema = RecordingStudioMcp::ToolDocs.endpoint_output_schema(
      endpoint_with_responses("200" => json_content({ "$ref" => "#/components/schemas/Chat" }))
    )

    assert_nil schema
  end

  def test_endpoint_output_schema_prefers_200_among_multiple_2xx
    schema = RecordingStudioMcp::ToolDocs.endpoint_output_schema(
      endpoint_with_responses(
        "201" => json_object_schema(created: { type: "boolean" }),
        "200" => json_object_schema(chats: { type: "array" })
      )
    )

    assert_equal "array", schema.dig(:properties, :chats, :type)
    refute schema.dig(:properties, :created)
  end

  def json_object_schema(**properties)
    json_content({ type: "object", properties: properties })
  end

  def json_content(schema)
    {
      content: {
        "application/json" => {
          schema: schema
        }
      }
    }
  end

  def endpoint_with_responses(responses)
    RecordingStudioApi::RegisteredEndpoint.new(
      name: :demo,
      http_verb: :get,
      path: "demo",
      handler: ->(_context) { {} },
      openapi: { responses: responses }
    )
  end
end
