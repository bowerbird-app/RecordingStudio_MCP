# frozen_string_literal: true

require "test_helper"

class McpFieldSchemaRecord
  Column = Struct.new(:type, :null, :default)
  Validator = Struct.new(:kind, :options)

  def self.columns_hash
    {
      "title" => Column.new(:string, false, nil),
      "priority" => Column.new(:integer, true, nil),
      "status" => Column.new(:string, true, nil)
    }
  end

  def self.validators_on(name)
    return [Validator.new(:inclusion, { in: %w[draft published] })] if name.to_s == "status"

    []
  end

  def self.defined_enums
    {}
  end
end

class FieldSchemaTest < Minitest::Test
  Registration = Struct.new(:writable_attributes, :immutable_fields, :openapi, keyword_init: true)

  def test_infers_types_requirements_allowed_values_and_immutability
    registration = Registration.new(
      writable_attributes: %i[title priority status],
      immutable_fields: %i[priority],
      openapi: {}
    )

    fields = RecordingStudioMcp::FieldSchema.for("McpFieldSchemaRecord", registration)
    title = fields.find { |field| field["name"] == "title" }
    priority = fields.find { |field| field["name"] == "priority" }
    status = fields.find { |field| field["name"] == "status" }

    assert_equal({ "name" => "title", "required" => true, "type" => "string" }, title)
    assert_equal "integer", priority["type"]
    assert_equal true, priority["immutable_on_update"]
    assert_equal %w[draft published], status["allowed_values"]
  end

  def test_prefers_openapi_field_metadata
    registration = Registration.new(
      writable_attributes: %i[priority],
      immutable_fields: [],
      openapi: {
        details_schema: {
          properties: {
            priority: { type: "number", enum: [1, 2], description: "Publishing priority." }
          },
          required: ["priority"]
        }
      }
    )

    field = RecordingStudioMcp::FieldSchema.for("McpFieldSchemaRecord", registration).first

    assert_equal "number", field["type"]
    assert_equal true, field["required"]
    assert_equal [1, 2], field["allowed_values"]
    assert_equal "Publishing priority.", field["description"]
  end

  def test_unknown_recordable_class_falls_back_to_string
    registration = Registration.new(writable_attributes: [:nickname], immutable_fields: [], openapi: {})

    assert_equal(
      [{ "name" => "nickname", "required" => false, "type" => "string" }],
      RecordingStudioMcp::FieldSchema.for("NotARealRecordable", registration)
    )
  end
end
