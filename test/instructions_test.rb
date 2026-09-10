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
      assert_includes text, "Call tools/list to see the available endpoint tools"
      assert_includes text, "fetch the detail before generating UI"
      assert_includes text, "Do not invent recordable types"
      assert_includes text, "unless tools/list advertises them"
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
      assert_includes text, "not under attributes"
      assert_includes text, "Use the endpoint tools"
      assert_includes text, "Call tools/list to see the available endpoint tools"
      assert_includes text, "fetch the detail before generating UI"
      assert_includes text, "Do not invent recordable types"
    end
  end

  def test_instructions_suffix_string_appended
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        RecordingStudioMcp.configuration.instructions_suffix = "Fetch item detail before you draw a screen."
        text = RecordingStudioMcp::Instructions.text

        assert_includes text, "call tools/list again"
        assert_operator text.index("call tools/list again"), :<, text.index("Fetch item detail before you draw a screen.")
        assert text.end_with?("Fetch item detail before you draw a screen.")
      end
    end
  end

  def test_instructions_suffix_callable_receives_access_grant
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        grant = Struct.new(:api_client).new(nil)
        received = nil
        RecordingStudioMcp.configuration.instructions_suffix = lambda { |access_grant:|
          received = access_grant
          "GRANT HINT"
        }

        text = RecordingStudioMcp::Instructions.text(access_grant: grant)

        assert_same grant, received
        assert_includes text, "GRANT HINT"
        assert text.end_with?("GRANT HINT")
      end
    end
  end

  def test_instructions_suffix_blank_omitted
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        baseline = RecordingStudioMcp::Instructions.text

        ["", "  ", nil].each do |suffix|
          RecordingStudioMcp.configuration.instructions_suffix = suffix
          text = RecordingStudioMcp::Instructions.text

          assert_equal baseline, text
          refute text.end_with?(" ")
        end
      end
    end
  end

  def test_tree_hosts_still_get_tree_blurb
    with_isolated_api_configuration do
      register_tree_type("Page")
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, RecordingStudioMcp::Instructions::TREE_BLURB
      assert_includes text, "Call describe before create"
      refute_includes text, "Use the endpoint tools"
    end
  end
end
