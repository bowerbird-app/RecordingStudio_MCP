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

  def test_list_form_adds_file_object_schema
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { "x-mcp-file-params": ["logo_file"] }))
    property = tool.dig(:inputSchema, :properties, :logo_file)

    assert_equal "object", property[:type]
    assert_equal FILE_KEYS, property[:properties].keys
    assert(property[:properties].values.all? { |schema| schema[:type] == "string" })
    assert_equal %w[download_url file_id], property[:required]
    assert_equal ["logo_file"], tool.dig(:_meta, "openai/fileParams")
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
    assert_equal ["logo_file"], tool.dig(:_meta, "openai/fileParams")
  end

  def test_path_tokens_are_never_file_fields
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { "x-mcp-file-params": %w[name logo_file] }))

    assert_equal "string", tool.dig(:inputSchema, :properties, :name, :type)
    assert_equal ["logo_file"], tool.dig(:_meta, "openai/fileParams")
    assert tool.dig(:inputSchema, :properties).key?(:logo_file)
  end

  def test_ignores_malformed_declarations
    tool = RecordingStudioMcp::Tools.endpoint_tool(endpoint(openapi: { "x-mcp-file-params": "logo_file" }))

    refute tool.key?(:_meta)
    refute tool.dig(:inputSchema, :properties).key?(:logo_file)
  end

  def test_registered_tool_keeps_the_file_object_and_advertises_file_params
    with_isolated_api_configuration do
      register_file_upload_action
      register_tree_type("Page", capability_actions: %i[create_upload])
      RecordingStudioMcp.register_tool(
        name: "create_upload",
        action: :create_upload,
        title: "Create upload",
        description: "Create an upload.",
        input: {},
        output: "the upload"
      )
      ensure_tree_server(:public, extra_tools: %w[create_upload])

      tool = RecordingStudioMcp::Tools.definitions.find { |entry| entry[:name] == "create_upload" }
      properties = tool.dig(:inputSchema, :properties)
      file = properties[:file]

      assert_equal "string", properties.dig(:url, :type)
      assert_equal "string", properties.dig(:data, :type)
      refute properties[:url].key?(:properties)
      refute properties[:data].key?(:properties)
      assert_equal "object", file[:type]
      assert_equal "File to upload.", file[:description]
      assert_equal "Temporary URL to download the file.", file.dig(:properties, :download_url, :description)
      assert_equal "File id.", file.dig(:properties, :file_id, :description)
      assert_equal "MIME type.", file.dig(:properties, :mime_type, :description)
      assert_equal "Original file name.", file.dig(:properties, :file_name, :description)
      assert_equal %w[download_url file_id], file[:required]
      refute_includes tool.dig(:inputSchema, :required), "file"
      assert_includes tool.dig(:inputSchema, :required), "url"
      assert_equal ["file"], tool.dig(:_meta, "openai/fileParams")
    end
  end

  def test_nested_object_keeps_properties_required_and_descriptions
    built = RecordingStudioMcp::SchemaFromContract.property(
      {
        type: "object",
        description: "Labels.",
        properties: {
          heading: { type: "string", description: "Section heading." }
        },
        required: %w[heading]
      }
    )

    assert_equal "object", built[:type]
    assert_equal "Labels.", built[:description]
    assert_equal "Section heading.", built.dig(:properties, :heading, :description)
    assert_equal ["heading"], built[:required]
    assert_empty RecordingStudioMcp::FileParams.field_names({ labels: built })

    kept = RecordingStudioMcp::SchemaFromContract.property(
      {
        type: "object",
        description: "File to upload.",
        properties: {
          download_url: { type: "string", description: "Temporary URL to download the file." },
          file_id: { type: "string", description: "File id." }
        },
        required: %w[file_id]
      }
    )

    assert_equal %w[file_id], kept[:required]
    assert_equal "Temporary URL to download the file.", kept.dig(:properties, :download_url, :description)
  end

  def test_schema_is_not_shared_between_tools
    first = RecordingStudioMcp::FileParams.property({})
    first[:properties][:download_url][:type] = "mutated"

    assert_equal "string", RecordingStudioMcp::FileParams.property({}).dig(:properties, :download_url, :type)
  end

  private

  def register_file_upload_action
    RecordingStudioApi.register_capability_action(
      :create_upload,
      capability: :attachable,
      input_contract: {
        fields: {
          url: { type: :string, required: true, description: "HTTPS URL of the file." },
          data: { type: :string, required: false, description: "Base64 file bytes." },
          file: {
            type: :hash,
            required: false,
            description: "File to upload.",
            properties: {
              download_url: { type: "string", description: "Temporary URL to download the file." },
              file_id: { type: "string", description: "File id." },
              mime_type: { type: "string", description: "MIME type." },
              file_name: { type: "string", description: "Original file name." }
            }
          }
        }
      },
      handler: ->(_context) { { json: { ok: true } } }
    )
  end

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
