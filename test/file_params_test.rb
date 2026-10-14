# frozen_string_literal: true

require "test_helper"

class FileParamsTest < Minitest::Test
  FILE_KEYS = %i[download_url file_id mime_type file_name].freeze

  def test_endpoints_without_file_params_are_unchanged
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { summary: "Plain" }))

    refute tool.key?(:_meta)
    assert_equal %i[name], tool.dig(:inputSchema, :properties).keys
    assert_empty RecordingStudioMcp::FileParams.names(endpoint)
  end

  def test_list_form_adds_file_object_schema_and_meta
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { "x-mcp-file-params": ["logo_file"] }))
    property = tool.dig(:inputSchema, :properties, :logo_file)

    assert_equal "object", property[:type]
    assert_equal FILE_KEYS, property[:properties].keys
    assert(property[:properties].values.all? { |schema| schema[:type] == "string" })
    assert_equal %w[download_url file_id], property[:required]
    assert_equal({ "openai/fileParams" => ["logo_file"] }, tool[:_meta])
    refute_includes tool.dig(:inputSchema, :required), "logo_file"
  end

  def test_hash_form_supports_nullable_required_and_description
    openapi = {
      "x-mcp-file-params" => {
        "icon_file" => { nullable: true, description: "Icon, or null to clear." },
        "cover_file" => { required: true }
      }
    }
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: openapi))
    icon = tool.dig(:inputSchema, :properties, :icon_file)
    cover = tool.dig(:inputSchema, :properties, :cover_file)

    assert_equal %w[object null], icon[:type]
    assert_equal "Icon, or null to clear.", icon[:description]
    assert_equal "object", cover[:type]
    refute cover.key?(:description)
    assert_includes tool.dig(:inputSchema, :required), "cover_file"
    refute_includes tool.dig(:inputSchema, :required), "icon_file"
    assert_equal %w[icon_file cover_file], tool.dig(:_meta, "openai/fileParams")
  end

  def test_file_param_replaces_a_contract_field_of_the_same_name
    contract = {
      reject_unknown: true,
      fields: { logo_file: { type: :string, required: false }, title: { type: :string } }
    }
    tool = RecordingStudioMcp::Tools.endpoint_tool(
      endpoint(openapi: { "x-mcp-file-params": ["logo_file"] }, input_contract: contract)
    )

    assert_equal "object", tool.dig(:inputSchema, :properties, :logo_file, :type)
    assert_equal "string", tool.dig(:inputSchema, :properties, :title, :type)
    assert_equal false, tool.dig(:inputSchema, :additionalProperties)
  end

  def test_path_tokens_are_never_file_fields
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { "x-mcp-file-params": %w[name logo_file] }))

    assert_equal "string", tool.dig(:inputSchema, :properties, :name, :type)
    assert_equal ["logo_file"], tool.dig(:_meta, "openai/fileParams")
  end

  def test_ignores_malformed_declarations
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { "x-mcp-file-params": "logo_file" }))

    refute tool.key?(:_meta)
    refute tool.dig(:inputSchema, :properties).key?(:logo_file)
  end

  def test_schema_is_not_shared_between_tools
    first = RecordingStudioMcp::FileParams.property({})
    first[:properties][:download_url][:type] = "mutated"

    assert_equal "string", RecordingStudioMcp::FileParams.property({}).dig(:properties, :download_url, :type)
  end

  private

  def endpoint(openapi: nil, input_contract: nil)
    RecordingStudioApi::RegisteredEndpoint.new(
      name: :upload_logo,
      http_verb: :patch,
      path: "logos/:name",
      handler: ->(_context) { {} },
      openapi: openapi,
      input_contract: input_contract
    )
  end
end
