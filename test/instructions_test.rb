# frozen_string_literal: true

require "test_helper"

class InstructionsTest < Minitest::Test
  include RecordableMetricToolHelpers

  def test_tree_only_uses_ordered_short_lines
    with_isolated_api_configuration do
      register_tree_type("Page")
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "## Sign in"
      assert_includes text, "Use an OAuth Bearer token. It has the same access as the app."
      assert_equal 1, text.scan("Call describe for the type paragraph").length
      assert_includes text,
                      "Call describe for the type paragraph, included tools, skills via read_skill, relationships, " \
                      "allowed parents, writable fields, and available actions before you create"
      assert_includes text, "notifications/tools/list_changed"
      assert_includes text, "ping checks the connection."
      assert_includes text, "Call list with the workspace type and no parent_id to find workspaces."
      assert_includes text, "Records nest by parent_id."
      assert_includes text, "root_id is the workspace, not the parent."
      assert_includes text, "not under attributes"
      assert_includes text, "idempotency_key when retrying a create, or a write action flagged creates: true,"
      assert_includes text, "with the same input. A different input for that key is an error."
      refute_includes text, "The key applies to create only."
      refute_includes text, "capability_action"
      assert_includes text, "pagination_token"
      refute_includes text, "List with parent_id, then show."
      refute_includes text, "If you only see named route tools"
      refute_includes text, "Oauth"
      refute_includes text, "recordable"
      refute_includes text, "generating UI"
      refute_includes text, "listChanged"
      assert_operator text.index("## Sign in"), :<, text.index("## Find your tools")
      assert_operator text.index("## Find your tools"), :<, text.index("## Walk your records")
      assert_operator text.index("## Walk your records"), :<, text.index("## Make changes")
      assert_operator text.index("## Make changes"), :<, text.index("## Guides")
    end
  end

  def test_catalog_only_puts_named_route_tools_last
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      include_api_endpoints
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "## If you only see named route tools"
      assert_includes text, "That is the whole set."
      assert_includes text, "One tool per named route. Path parameters are arguments."
      assert_includes text, "notifications/tools/list_changed"
      assert_includes text, "ping checks the connection."
      refute_includes text, "Call describe for the type paragraph"
      refute_includes text, "Records nest by parent_id."
      refute_includes text, "generating UI"
      refute_includes text, "recordable"
      assert text.end_with?("One tool per named route. Path parameters are arguments.")
    end
  end

  def test_mixed_surface_omits_the_endpoint_only_line
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      include_api_endpoints(tree: true)
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, describe_sentence
      assert_includes text, "plus named route tools"
      refute_includes text, "If you only see named route tools"
      refute_includes text, "generating UI"
    end
  end

  def test_tree_mentions_list_parent_id_when_advertised
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        RecordingStudioMcp.configuration.list_parent_id_types = %w[Page]
        text = RecordingStudioMcp::Instructions.text

        assert_includes text, "List with parent_id, then show."
        assert_operator text.index("no parent_id"), :<, text.index("List with parent_id, then show.")
      end
    end
  end

  def test_view_only_grant_omits_make_changes_and_write_tools
    with_isolated_api_configuration do
      register_ping_capability(required_role: :view)
      register_tree_type(
        "Page",
        operations: %i[index show create update destroy],
        capability_actions: %i[ping]
      )
      view = RecordingStudioMcp::Instructions.text(access_grant: role_grant(:view))
      full = RecordingStudioMcp::Instructions.text

      assert_includes full, "## Make changes"
      assert_includes full, "create, update, delete"
      refute_includes view, "## Make changes"
      refute_includes view, "create, update, delete"
      refute_includes view, "view-only connection"
      assert_includes view, "list, show, capability_action, describe, read_skill, and ping"
    end
  end

  def test_read_only_tree_omits_create_guidance
    with_isolated_api_configuration do
      register_tree_type("SupportPage", operations: %i[index show])
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "#{describe_sentence}."
      refute_includes text, "before you create"
      assert_includes text, "pagination_token"
      refute_includes text, "not under attributes"
      refute_includes text, "idempotency_key"
      refute_includes text, "## Make changes"
    end
  end

  def test_full_tree_mentions_create_and_capability_action_once
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type("Page", operations: %i[index show create update destroy], capability_actions: %i[ping])
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "before you create or run an action."
      assert_equal 1, text.scan("Call describe for the type paragraph").length
      assert_includes text, "list, show, create, update, delete, capability_action, describe, read_skill, and ping"
    end
  end

  def test_instructions_suffix_string_sits_under_guides
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        RecordingStudioMcp.configuration.instructions_suffix = "Read the host guide before you write."
        text = RecordingStudioMcp::Instructions.text

        skill_at = text.index("Call read_skill with the name.")
        guide_at = text.index("Read the host guide before you write.")
        assert_operator skill_at, :<, guide_at
        assert text.end_with?("Read the host guide before you write.")
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
          access_grant ? "Grant guide" : "Docs guide"
        }

        granted = RecordingStudioMcp::Instructions.text(access_grant: grant)
        assert_same grant, received
        docs = RecordingStudioMcp::Instructions.text
        assert_includes granted, "Grant guide"
        assert granted.end_with?("Grant guide")
        assert_includes docs, "Docs guide"
        refute_includes docs, "Grant guide"
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

  def test_metric_tools_add_one_filter_sentence
    with_isolated_api_configuration do
      register_tree_type("Page")
      without_metrics = RecordingStudioMcp::Instructions.text
      refute_includes without_metrics, "filter object of attribute names"

      with_recordable_metric_registry do
        register_folder_and_page_metrics
        include_metric_server
        text = RecordingStudioMcp::Instructions.text

        assert_includes text, "## Metrics"
        assert_includes text, "filter object of attribute names"
        assert_equal 1, text.scan("filter object of attribute names").length
        assert_operator text.index("## Guides"), :<, text.index("## Metrics")
      end
    end
  end

  def describe_sentence
    "Call describe for the type paragraph, included tools, skills via read_skill, " \
      "relationships, allowed parents, writable fields, and available actions"
  end

  def test_tree_hosts_still_get_the_walk_and_not_the_endpoint_only_line
    with_isolated_api_configuration do
      register_tree_type("Page")
      text = RecordingStudioMcp::Instructions.text

      assert_includes text, "## Walk your records"
      refute_includes text, "If you only see named route tools"
    end
  end
end
