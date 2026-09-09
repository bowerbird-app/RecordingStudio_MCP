# frozen_string_literal: true

require "test_helper"

class InstructionsTest < Minitest::Test
  def test_tree_only_includes_describe_guidance
    with_isolated_api_configuration do
      register_tree_type("Page")
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "both this MCP endpoint and the Recording Studio API"
      assert_includes text, "Call describe before create"
      assert_includes text, "not under attributes"
      assert_includes text, "pagination_token"
      assert_includes text, "call tools/list again"
      refute_includes text, "Use the endpoint tools"
    end
  end

  def test_catalog_only_omits_describe_guidance
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "Use the endpoint tools"
      assert_includes text, "Path parameters are tool arguments"
      assert_includes text, "call tools/list again"
      refute_includes text, "Call describe before create"
    end
  end

  def test_mixed_includes_both_guidance_blocks
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "Call describe before create"
      assert_includes text, "Use the endpoint tools"
    end
  end
end
