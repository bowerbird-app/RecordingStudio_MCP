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
end
