# frozen_string_literal: true

require "digest"
require "fileutils"
require "test_helper"
require "tmpdir"

class SkillsTest < Minitest::Test
  SKILL_SENTENCE = "This server may provide skills containing additional guidance for completing tasks with these " \
                   "tools. Discover and use relevant skills when appropriate."
  DESCRIPTION = "Research publication guidance."

  def setup
    @grant = Struct.new(:api_client).new(nil)
  end

  def test_register_skill_stores_a_skill_another_caller_can_list
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.binwrite("SKILL.md", skill_text("research-publications", "Use the house style.\n"))
          RecordingStudioMcp.register_skill("research-publications", path: "SKILL.md")
        end

        stored = RecordingStudioMcp.configuration.skill_catalog.fetch("research-publications")
        expected_path = Pathname.new(File.expand_path("SKILL.md", dir))

        assert_equal expected_path, stored.path
        assert_equal "research-publications", stored.name
        assert_equal "skill://research-publications/SKILL.md", stored.uri
        assert_equal(
          success_body(skills: [card_for("research-publications", "Use the house style.\n")]),
          handle("skills/list").body
        )
      end
    end
  end

  def test_resources_read_returns_the_registered_skill_file_text
    with_skill("research-publications", "Use the house style.\n") do |_dir, _path|
      result = handle("resources/read", params: { "uri" => "skill://research-publications/SKILL.md" })

      assert_equal(
        success_body(contents: [content_for("research-publications", "Use the house style.\n")]),
        result.body
      )
    end
  end

  def test_initialize_capabilities_advertise_skills
    with_isolated_mcp_configuration do
      result = handle("initialize", params: { "protocolVersion" => "2025-06-18" })

      assert_equal(
        {
          tools: { listChanged: false },
          resources: {},
          extensions: { "io.modelcontextprotocol/skills" => {} }
        },
        result.body.dig(:result, :capabilities)
      )
    end
  end

  def test_initialize_instructions_include_the_skill_sentence
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        result = handle("initialize", params: { "protocolVersion" => "2025-06-18" })

        assert_includes result.body.dig(:result, :instructions), SKILL_SENTENCE
      end
    end
  end

  def test_skills_list_returns_the_exposed_skill_card
    body = "Use the house style.\n"
    with_skill("research-publications", body) do
      listed = handle("skills/list").body
      listed_with_nil_cursor = handle("skills/list", params: { "cursor" => nil }).body
      card = card_for("research-publications", body)

      assert_equal success_body(skills: [card]), listed
      assert_equal listed, listed_with_nil_cursor
      listed_card = listed.dig(:result, :skills, 0)
      assert_equal "skill://research-publications/SKILL.md", listed_card[:uri]
      assert_equal "research-publications", listed_card[:frontmatter]["name"]
      assert_equal DESCRIPTION, listed_card[:frontmatter]["description"]
      assert_equal card[:resources], listed_card[:resources]
    end
  end

  def test_skill_policy_hides_a_skill_from_list_get_and_read
    body = "HIDDEN-FILE-TEXT\n"
    with_skill("hidden-research", body) do
      RecordingStudioMcp.configuration.skill_policy = lambda { |skill:, access_grant:|
        skill.name == "unused" && access_grant.nil?
      }
      listed = handle("skills/list")
      fetched = handle("skills/get", params: { "uri" => "skill://hidden-research/SKILL.md" })
      read = handle("resources/read", params: { "uri" => "skill://hidden-research/SKILL.md" })

      assert_equal success_body(skills: []), listed.body
      assert_invalid fetched
      assert_invalid read
      refute_includes fetched.body.inspect, "hidden-research"
      refute_includes read.body.inspect, "HIDDEN-FILE-TEXT"
      refute_includes listed.body.inspect, "hidden-research"
    end
  end

  def test_skills_get_returns_the_card_for_an_exposed_skill
    body = "Use the house style.\n"
    with_skill("research-publications", body) do
      result = handle("skills/get", params: { "uri" => "skill://research-publications/SKILL.md" })

      assert_equal success_body(skill: card_for("research-publications", body)), result.body
    end
  end

  def test_unknown_skill_uri_is_invalid_params
    with_isolated_mcp_configuration do
      result = handle("skills/get", params: { "uri" => "skill://missing-skill/SKILL.md" })

      assert_invalid result
    end
  end

  def test_unknown_resource_uri_is_invalid_params
    with_isolated_mcp_configuration do
      result = handle("resources/read", params: { "uri" => "skill://missing-skill/SKILL.md" })

      assert_invalid result
    end
  end

  def test_resources_read_rejects_passwd_path
    with_isolated_mcp_configuration do
      result = handle("resources/read", params: { "uri" => "/etc/passwd" })

      assert_invalid result
      refute_includes result.body.inspect, "root:"
    end
  end

  def test_resources_read_rejects_traversal_uris_without_reading_a_sibling_secret
    secret = "TOP-SECRET-SIBLING\n"
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        outside = nil
        skill_dir = File.join(dir, "research-publications")
        FileUtils.mkdir_p(skill_dir)
        File.binwrite(File.join(skill_dir, "SKILL.md"), skill_text("research-publications", "Use the house style.\n"))
        File.binwrite(File.join(dir, "secret"), secret)
        File.binwrite(File.join(skill_dir, "secret"), secret)
        outside = File.expand_path("../../secret", skill_dir)
        FileUtils.mkdir_p(File.dirname(outside))
        File.binwrite(outside, secret)
        RecordingStudioMcp.register_skill("research-publications", path: File.join(skill_dir, "SKILL.md"))

        [
          "skill://research-publications/../../secret",
          "skill://../etc/passwd/SKILL.md"
        ].each do |uri|
          result = handle("resources/read", params: { "uri" => uri })

          assert_invalid result
          refute_includes result.body.inspect, "TOP-SECRET-SIBLING"
        end
      ensure
        FileUtils.rm_f(outside) if outside
      end
    end
  end

  def test_available_if_false_hides_list_get_and_read
    body = "GRANT-HIDDEN-TEXT\n"
    seen = []
    with_skill("grant-hidden", body, available_if: lambda { |access_grant:|
      seen << access_grant
      false
    }) do
      listed = handle("skills/list")
      fetched = handle("skills/get", params: { "uri" => "skill://grant-hidden/SKILL.md" })
      read = handle("resources/read", params: { "uri" => "skill://grant-hidden/SKILL.md" })

      assert_equal success_body(skills: []), listed.body
      assert_invalid fetched
      assert_invalid read
      refute_includes read.body.inspect, "GRANT-HIDDEN-TEXT"
      assert_includes seen, @grant
    end
  end

  def test_available_if_receives_the_same_access_grant
    seen = nil
    with_skill("research-publications", "Use the house style.\n", available_if: lambda { |access_grant:|
      seen = access_grant
      true
    }) do
      handle("skills/list")

      assert_same @grant, seen
    end
  end

  def test_skill_policy_false_hides_a_registered_skill
    with_skill("research-publications", "Use the house style.\n") do
      RecordingStudioMcp.configuration.skill_policy = lambda { |skill:, access_grant:|
        skill.nil? && access_grant.nil?
      }

      assert_equal success_body(skills: []), handle("skills/list").body
    end
  end

  def test_skill_policy_receives_the_skill_and_the_same_access_grant
    seen_skill = nil
    seen_grant = nil
    with_skill("research-publications", "Use the house style.\n") do |_dir, path|
      RecordingStudioMcp.configuration.skill_policy = lambda { |skill:, access_grant:|
        seen_skill = skill
        seen_grant = access_grant
        true
      }
      handle("skills/list")

      assert_equal "research-publications", seen_skill.name
      assert_equal Pathname.new(File.expand_path(path)), seen_skill.path
      assert_equal "skill://research-publications/SKILL.md", seen_skill.uri
      assert_same @grant, seen_grant
    end
  end

  def test_available_if_and_skill_policy_must_both_allow_exposure
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        register_named(dir, "visible", available_if: ->(access_grant:) { access_grant.equal?(@grant) })
        register_named(dir, "policy-hides", available_if: ->(access_grant:) { access_grant.equal?(@grant) })
        register_named(dir, "grant-hides", available_if: ->(access_grant:) { !access_grant.equal?(@grant) })
        RecordingStudioMcp.configuration.skill_policy = lambda { |skill:, access_grant:|
          assert_same @grant, access_grant
          skill.name != "policy-hides"
        }

        assert_equal(
          success_body(skills: [card_for("visible", "Body for visible.\n")]),
          handle("skills/list").body
        )
        assert_equal(
          success_body(skill: card_for("visible", "Body for visible.\n")),
          handle("skills/get", params: { "uri" => "skill://visible/SKILL.md" }).body
        )
        assert_invalid handle("skills/get", params: { "uri" => "skill://policy-hides/SKILL.md" })
        assert_invalid handle("skills/get", params: { "uri" => "skill://grant-hides/SKILL.md" })
      end
    end
  end

  def test_tools_list_for_a_tree_grant_ignores_registered_skills
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        Dir.mktmpdir do |dir|
          register_tree_type
          path = write_skill(dir, "research-publications", "Use the house style.\n")
          RecordingStudioMcp.register_skill("research-publications", path: path)
          result = handle("tools/list", id: 2)
          names = result.body.dig(:result, :tools).map { |tool| tool[:name] }

          assert_equal %w[list show create update capability_action describe], names
        end
      end
    end
  end

  def test_tools_call_still_dispatches
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        path = write_skill(dir, "research-publications", "Use the house style.\n")
        RecordingStudioMcp.register_skill("research-publications", path: path)
        stub_result = {
          content: [{ type: "text", text: "{}" }],
          structuredContent: {},
          isError: false
        }
        RecordingStudioMcp::Dispatcher.stub(:call, stub_result) do
          result = handle(
            "tools/call",
            params: { "name" => "list", "arguments" => { "type" => "Workspace" } },
            id: 7
          )

          assert_equal false, result.body.dig(:result, :isError)
        end
      end
    end
  end

  def test_initialize_keeps_tree_and_endpoint_instruction_split
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type
        tree = handle("initialize", params: { "protocolVersion" => "2025-06-18" })
        tree_text = tree.body.dig(:result, :instructions)

        assert_includes tree_text, "Call describe before create"
        assert_includes tree_text, SKILL_SENTENCE
        refute_includes tree_text, "Use the endpoint tools"
      end
    end

    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        RecordingStudioApi.register_endpoint(
          :ping,
          http_verb: :get,
          path: "ping",
          handler: ->(_context) { { ok: true } }
        )
        endpoint = handle("initialize", params: { "protocolVersion" => "2025-06-18" })
        endpoint_text = endpoint.body.dig(:result, :instructions)

        assert_includes endpoint_text, "Use the endpoint tools"
        assert_includes endpoint_text, SKILL_SENTENCE
        refute_includes endpoint_text, "Call describe before create"
      end
    end
  end

  def test_instructions_suffix_stays_after_the_skill_sentence
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        RecordingStudioMcp.configuration.instructions_suffix = "GRANT HINT"
        text = RecordingStudioMcp::Instructions.text(access_grant: @grant)
        initialized = handle("initialize", params: { "protocolVersion" => "2025-06-18" })
        instructions = initialized.body.dig(:result, :instructions)

        assert text.end_with?("GRANT HINT")
        assert instructions.end_with?("GRANT HINT")
        assert_operator text.index(SKILL_SENTENCE), :<, text.index("GRANT HINT")
        assert_operator instructions.index(SKILL_SENTENCE), :<, instructions.index("GRANT HINT")
      end
    end
  end

  def test_missing_exposed_file_is_unavailable_without_the_temp_path
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "research-publications-SKILL.md")
        RecordingStudioMcp.register_skill("research-publications", path: path)
        listed = handle("skills/list")
        fetched = handle("skills/get", params: { "uri" => "skill://research-publications/SKILL.md" })
        read = handle("resources/read", params: { "uri" => "skill://research-publications/SKILL.md" })

        [listed, fetched, read].each do |result|
          assert_unavailable result
          refute_includes result.body.inspect, path
          refute_includes result.body.inspect, dir
        end
      end
    end
  end

  def test_hidden_missing_file_is_invalid_params
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hidden-research-SKILL.md")
        RecordingStudioMcp.register_skill(
          "hidden-research",
          path: path,
          available_if: ->(access_grant:) { access_grant.nil? }
        )
        RecordingStudioMcp.configuration.skill_policy = lambda { |skill:, access_grant:|
          skill.name == "hidden-research" && access_grant.equal?(@grant)
        }
        listed = handle("skills/list")
        fetched = handle("skills/get", params: { "uri" => "skill://hidden-research/SKILL.md" })
        read = handle("resources/read", params: { "uri" => "skill://hidden-research/SKILL.md" })

        assert_equal success_body(skills: []), listed.body
        assert_invalid fetched
        assert_invalid read
        refute_includes fetched.body.inspect, path
        refute_includes read.body.inspect, path
      end
    end
  end

  def test_skills_list_rejects_a_cursor_and_non_hash_params
    with_isolated_mcp_configuration do
      assert_invalid handle("skills/list", params: { "cursor" => "next" })
      assert_invalid handle("skills/list", params: [])
    end
  end

  def test_reregistering_the_same_name_replaces_the_file
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        first = write_skill(dir, "research-publications", "FIRST-BODY\n")
        second = write_skill(File.join(dir, "next"), "research-publications", "SECOND-BODY\n")
        other = write_skill(dir, "other-skill", "OTHER-BODY\n")
        RecordingStudioMcp.register_skill("research-publications", path: first)
        RecordingStudioMcp.register_skill("other-skill", path: other)
        RecordingStudioMcp.register_skill("research-publications", path: second)
        read = handle("resources/read", params: { "uri" => "skill://research-publications/SKILL.md" })
        names = handle("skills/list").body.dig(:result, :skills).map { |card| card[:frontmatter]["name"] }

        assert_equal success_body(contents: [content_for("research-publications", "SECOND-BODY\n")]), read.body
        refute_includes read.body.inspect, "FIRST-BODY"
        assert_equal %w[research-publications other-skill], names
      end
    end
  end

  def test_register_skill_rejects_a_bad_name
    with_isolated_mcp_configuration do
      assert_raises(ArgumentError) do
        RecordingStudioMcp.register_skill("../etc", path: "/tmp/not-a-skill")
      end
    end
  end

  def test_non_callable_policy_hides_every_skill
    with_skill("research-publications", "Use the house style.\n") do
      RecordingStudioMcp.configuration.skill_policy = "allow"

      assert_equal success_body(skills: []), handle("skills/list").body
      assert_invalid handle("skills/get", params: { "uri" => "skill://research-publications/SKILL.md" })
    end
  end

  def test_skills_list_notification_accepts_success_and_returns_errors
    with_isolated_mcp_configuration do
      accepted = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "method" => "skills/list", "params" => {} },
        access_grant: @grant
      )
      rejected = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "method" => "skills/list", "params" => { "cursor" => "next" } },
        access_grant: @grant
      )

      assert_equal :accepted, accepted.status
      assert_equal true, accepted.notification
      assert_nil accepted.body
      assert_invalid rejected, id: nil
    end
  end

  def test_frontmatter_fields_pass_through_on_the_card
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "research-publications-SKILL.md")
        text = <<~MARKDOWN
          ---
          name: research-publications
          description: #{DESCRIPTION}
          license: Apache-2.0
          tags:
            - publications
          ---
          Use the house style.
        MARKDOWN
        File.binwrite(path, text)
        RecordingStudioMcp.register_skill("research-publications", path: path)
        frontmatter = handle(
          "skills/get",
          params: { "uri" => "skill://research-publications/SKILL.md" }
        ).body.dig(:result, :skill, :frontmatter)

        assert_equal "Apache-2.0", frontmatter["license"]
        assert_equal ["publications"], frontmatter["tags"]
        assert_equal text, handle("resources/read", params: { "uri" => "skill://research-publications/SKILL.md" })
          .body.dig(:result, :contents, 0, :text)
      end
    end
  end

  def test_malformed_skill_file_is_unavailable_without_the_path
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "research-publications-SKILL.md")
        File.binwrite(path, "---\nname: [\n---\n")
        RecordingStudioMcp.register_skill("research-publications", path: path)
        result = handle("resources/read", params: { "uri" => "skill://research-publications/SKILL.md" })

        assert_unavailable result
        refute_includes result.body.inspect, path
      end
    end
  end

  def test_one_unreadable_exposed_skill_fails_the_whole_list
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        kept = write_skill(dir, "research-publications", "Use the house style.\n")
        missing = File.join(dir, "other-skill-SKILL.md")
        RecordingStudioMcp.register_skill("research-publications", path: kept)
        RecordingStudioMcp.register_skill("other-skill", path: missing)

        assert_unavailable handle("skills/list")
      end
    end
  end

  private

  def handle(method, params: {}, id: 1)
    RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params },
      access_grant: @grant
    )
  end

  def with_skill(name, body, available_if: nil)
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        path = write_skill(dir, name, body)
        RecordingStudioMcp.register_skill(name, path: path, available_if: available_if)
        yield dir, path
      end
    end
  end

  def register_named(dir, name, available_if:)
    path = write_skill(dir, name, "Body for #{name}.\n")
    RecordingStudioMcp.register_skill(name, path: path, available_if: available_if)
  end

  def write_skill(dir, name, body)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "#{name}-SKILL.md")
    File.binwrite(path, skill_text(name, body))
    path
  end

  def skill_text(name, body)
    "---\nname: #{name}\ndescription: #{DESCRIPTION}\n---\n#{body}"
  end

  def card_for(name, body)
    text = skill_text(name, body)
    uri = "skill://#{name}/SKILL.md"
    {
      uri: uri,
      frontmatter: { "name" => name, "description" => DESCRIPTION },
      resources: [{ uri: uri, digest: "sha256:#{Digest::SHA256.hexdigest(text)}", size: text.bytesize }]
    }
  end

  def content_for(name, body)
    { uri: "skill://#{name}/SKILL.md", mimeType: "text/markdown", text: skill_text(name, body) }
  end

  def success_body(id: 1, **payload)
    {
      jsonrpc: "2.0",
      id: id,
      result: { resultType: "complete", **payload, ttlMs: 0, cacheScope: "private" }
    }
  end

  def assert_invalid(result, id: 1)
    assert_equal({ jsonrpc: "2.0", id: id, error: { code: -32_602, message: "Invalid params" } }, result.body)
  end

  def assert_unavailable(result, id: 1)
    assert_equal(
      { jsonrpc: "2.0", id: id, error: { code: -32_603, message: "Skill content is unavailable" } },
      result.body
    )
  end
end
