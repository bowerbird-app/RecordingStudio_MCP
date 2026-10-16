# frozen_string_literal: true

require "test_helper"

class EndpointSchemaTest < Minitest::Test
  def test_path_tokens_are_required_strings
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :show_component,
      http_verb: :get,
      path: "flatpack/components/:name",
      handler: ->(_context) { {} }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal "object", schema[:type]
    assert_equal ["name"], schema[:required]
    assert_equal "string", schema.dig(:properties, :name, :type)
    refute schema.key?(:additionalProperties)
  end

  def test_contract_fields_map_types_enum_and_required
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :search,
      http_verb: :post,
      path: "search",
      handler: ->(_context) { {} },
      input_contract: {
        fields: {
          q: { type: :string, required: true, description: "Search query" },
          limit: { type: :integer, required: false },
          style: { type: :string, required: false, enum: %w[quiet loud] },
          flags: { type: :hash, required: false }
        }
      }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal ["q"], schema[:required]
    assert_equal "string", schema.dig(:properties, :q, :type)
    assert_equal "integer", schema.dig(:properties, :limit, :type)
    assert_equal "object", schema.dig(:properties, :flags, :type)
    assert_equal %w[quiet loud], schema.dig(:properties, :style, :enum)
    assert_equal false, schema[:additionalProperties]
    assert_equal "Search query", schema.dig(:properties, :q, :description)
  end

  def test_reject_unknown_false_leaves_additional_properties_open
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :search,
      http_verb: :post,
      path: "search",
      handler: ->(_context) { {} },
      input_contract: {
        reject_unknown: false,
        fields: {
          q: { type: :string, required: false }
        }
      }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    refute schema.key?(:additionalProperties)
  end

  def test_path_tokens_win_on_name_collision
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :echo,
      http_verb: :post,
      path: "echo/:key",
      handler: ->(_context) { {} },
      input_contract: {
        fields: {
          key: { type: :integer, required: false, enum: [1, 2] },
          message: { type: :string, required: true }
        }
      }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal "string", schema.dig(:properties, :key, :type)
    refute schema.dig(:properties, :key).key?(:enum)
    assert_equal "string", schema.dig(:properties, :message, :type)
    assert_includes schema[:required], "key"
    assert_includes schema[:required], "message"
  end

  def test_openapi_query_parameters_become_properties
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :metrics_show,
      http_verb: :get,
      path: "metrics/:resource/:name",
      handler: ->(_context) { {} },
      openapi: {
        parameters: [
          { name: "from", in: "query", description: "Alias for start.",
            schema: { type: "string", format: "date-time" } },
          { name: "interval", in: "query", required: true, schema: { type: "string", enum: %w[day week] } },
          { name: "resource", in: "path", description: "Ignored here." },
          { name: "X-Trace", in: "header", schema: { type: "string" } }
        ]
      }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal({ type: "string", format: "date-time", description: "Alias for start." },
                 schema.dig(:properties, :from))
    assert_equal %w[day week], schema.dig(:properties, :interval, :enum)
    assert_equal %w[resource name interval], schema[:required]
    assert_equal({ type: "string", description: "Path parameter resource." }, schema.dig(:properties, :resource))
    refute schema[:properties].key?(:"X-Trace")
    refute schema.key?(:additionalProperties)
  end

  def test_users_style_write_endpoint_without_a_contract_has_no_body_fields
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :users_create,
      http_verb: :post,
      path: "users",
      handler: ->(_context) { {} },
      openapi: { summary: "Create a user", description: "Requires Accessible :edit on AdminRoot." }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal({}, schema[:properties])
    assert_equal [], schema[:required]
  end

  def test_users_style_update_exposes_the_path_id_only_without_a_contract
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :users_update,
      http_verb: :patch,
      path: "users/:id",
      handler: ->(_context) { {} },
      openapi: { summary: "Update a user" }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal %w[id], schema[:required]
    assert_equal({ type: "string", description: "Path parameter id." }, schema.dig(:properties, :id))
    refute schema[:properties].key?(:email)
  end
end
