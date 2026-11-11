# frozen_string_literal: true

require "test_helper"

class OutputSchemaCheckTest < ActiveSupport::TestCase
  test "required and enum are enforced" do
    schema = {
      "type" => "object",
      "required" => ["kind"],
      "properties" => {
        "kind" => {
          "type" => "string",
          "enum" => %w[list show]
        }
      },
      "additionalProperties" => false
    }

    assert_empty OutputSchemaCheck.errors(schema, { "kind" => "list" })
    assert_includes OutputSchemaCheck.errors(schema, {}), "$.kind is required"
    assert_includes(
      OutputSchemaCheck.errors(schema, { "kind" => "metric" }),
      '$.kind must be one of ["list", "show"]'
    )
    assert_includes OutputSchemaCheck.errors(schema, { "kind" => "list", "extra" => 1 }), "$.extra is not allowed"
  end
end
