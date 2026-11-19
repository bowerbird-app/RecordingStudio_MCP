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
          flags: { type: :hash, required: false },
          tags: { type: :array, required: false, items: { type: "string" } },
          meta: {
            type: :hash,
            required: false,
            properties: { heading: { type: "string" } }
          }
        }
      }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)
    copied = RecordingStudioMcp::EndpointSchema.build(endpoint, copy: { "q" => { description: "Search query" } })

    assert_equal ["q"], schema[:required]
    assert_equal "string", schema.dig(:properties, :q, :type)
    assert_equal "integer", schema.dig(:properties, :limit, :type)
    assert_equal "object", schema.dig(:properties, :flags, :type)
    assert_equal %w[quiet loud], schema.dig(:properties, :style, :enum)
    assert_equal "array", schema.dig(:properties, :tags, :type)
    assert_equal({ type: "string" }, schema.dig(:properties, :tags, :items))
    assert_equal "object", schema.dig(:properties, :meta, :type)
    assert_equal({ heading: { type: "string" } }, schema.dig(:properties, :meta, :properties))
    assert_equal 1, schema.dig(:properties, :q, :minLength)
    assert_equal false, schema[:additionalProperties]
    refute schema.dig(:properties, :q).key?(:description)
    assert_equal "Search query", copied.dig(:properties, :q, :description)
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
          { name: "resource", in: "path", description: "Which metric family." },
          { name: "X-Trace", in: "header", schema: { type: "string" } }
        ]
      }
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal({ type: "string", format: "date-time", description: "Alias for start." },
                 schema.dig(:properties, :from))
    assert_equal %w[day week], schema.dig(:properties, :interval, :enum)
    assert_equal %w[resource name interval], schema[:required]
    assert_equal({ type: "string", description: "Which metric family." }, schema.dig(:properties, :resource))
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
    assert_equal({ type: "string", description: "The user id." }, schema.dig(:properties, :id))
    refute schema[:properties].key?(:email)
  end

  def test_undescribed_path_id_uses_the_registered_resource
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :show,
      http_verb: :get,
      path: "conversations/:id",
      recordable_type: "Conversation",
      handler: ->(_context) {}
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal "The conversation id.", schema.dig(:properties, :id, :description)
  end

  def test_undescribed_path_id_uses_the_endpoint_name_when_there_is_no_resource
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :conversations_show,
      http_verb: :get,
      path: "conversations/:id",
      scope_id: false,
      handler: ->(_context) {}
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal "The conversation id.", schema.dig(:properties, :id, :description)
  end

  def test_undescribed_path_parameter_without_a_resource_uses_a_clear_sentence
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :show,
      http_verb: :get,
      path: ":id",
      scope_id: false,
      handler: ->(_context) {}
    )

    schema = RecordingStudioMcp::EndpointSchema.build(endpoint)

    assert_equal "The id in the request path.", schema.dig(:properties, :id, :description)
  end

  def test_path_description_lookup_failure_still_builds_the_schema
    endpoint = RecordingStudioApi::RegisteredEndpoint.new(
      name: :show,
      http_verb: :get,
      path: ":id",
      recordable_type: "Conversation",
      scope_id: false,
      handler: ->(_context) {}
    )
    warnings = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(warnings)

    schema = RecordingStudioApi.stub(:resource_name_for, ->(*) { raise "missing conversation" }) do
      RecordingStudioMcp::EndpointSchema.build(endpoint)
    end

    assert_equal "The id in the request path.", schema.dig(:properties, :id, :description)
    assert_includes warnings.string, "show"
    assert_includes warnings.string, "id"
  ensure
    Rails.logger = previous if previous
  end
end
