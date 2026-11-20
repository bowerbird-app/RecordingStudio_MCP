# frozen_string_literal: true

require "test_helper"

class RegistrationsTest < Minitest::Test
  def test_tools_list_is_opt_in_on_the_server
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :show }

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[show describe], names
    end
  end

  def test_describe_is_always_present
    with_isolated_api_configuration do
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools }

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal ["describe"], names
    end
  end

  def test_host_override_changes_title_only
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_tool(
        name: "list",
        operation: :index,
        title: "Find pages",
        description: "Host list copy.",
        input: {},
        output: "records"
      )

      list = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "list" }

      assert_equal "Find pages", list[:title]
    end
  end

  def test_override_cannot_change_target
    with_isolated_api_configuration do
      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.register_tool(
          name: "list",
          operation: :show,
          title: "List",
          description: "Wrong target.",
          input: {},
          output: "records"
        )
      end

      assert_includes error.message, "cannot change type or target"
    end
  end

  def test_unknown_field_on_a_typed_tool_raises
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :echo,
        http_verb: :post,
        path: "echo",
        handler: ->(_context) { { ok: true } },
        input_contract: { fields: { style: { type: :string, required: false } } }
      )
      RecordingStudioMcp.register_tool(
        name: "echo",
        endpoint: :echo,
        title: "Echo",
        description: "Echo a style.",
        input: { "not_a_field" => { description: "nope" } },
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :echo }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "not_a_field"
    end
  end

  def test_sensitive_tool_requires_allow_sensitive
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :secret_ping,
        http_verb: :get,
        path: "secret-ping",
        handler: ->(_context) { { ok: true } },
        sensitive: true
      )
      RecordingStudioMcp.register_tool(
        name: "secret_ping",
        endpoint: :secret_ping,
        title: "Secret ping",
        description: "A ping that is marked sensitive.",
        input: {},
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :secret_ping }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "allow_sensitive"
    end
  end

  def test_per_tool_allow_sensitive_includes_a_sensitive_item
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :secret_ping,
        http_verb: :get,
        path: "secret-ping",
        handler: ->(_context) { { ok: true } },
        sensitive: true
      )
      RecordingStudioMcp.register_tool(
        name: "secret_ping",
        endpoint: :secret_ping,
        title: "Secret ping",
        description: "A ping that is marked sensitive.",
        input: {},
        output: "ok"
      )
      RecordingStudioMcp.register_server(:public, api: :public) do
        include_tool :secret_ping, allow_sensitive: true
      end

      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_includes names, "secret_ping"
    end
  end

  def test_describe_uses_register_type_and_hydrates_write_shape
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_type(type: "Page", description: "A page under a folder or workspace.")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      payload = catalog.describe("Page")

      assert_equal "A page under a folder or workspace.", payload["description"]
      assert_includes payload["tools"], "list"
      assert_equal [], payload["skills"]
      assert payload.key?("relationships")
      assert payload.key?("parent")
      title = payload.fetch("writable_fields").find { |field| field["name"] == "title" }
      assert_equal "string", title["type"]
      assert_equal [], payload.fetch("capability_actions")
    end
  end

  def test_dispatch_rejects_a_tool_not_on_the_server
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :show }
      grant = role_grant(:edit)
      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "list",
        arguments: { "type" => "Page" },
        access_grant: grant
      )

      assert_equal true, result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool list"
    end
  end

  def test_override_copy_cannot_change_lookup_schema
    with_isolated_api_configuration do
      register_tree_type("Page", writable_attributes: %i[title])
      RecordingStudioApi.register_resource_handler(
        "Page",
        :create,
        handler: ->(_) { { json: { id: "1", type: "Page" } } }
      )
      create_name = RecordingStudioMcp.tool_name("Page", :create)
      RecordingStudioMcp.register_tool(
        name: create_name,
        type: "Page",
        operation: :create,
        title: "Create page",
        description: "Create a page.",
        input: {},
        output: "the page"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools create_name }
      RecordingStudioMcp.register_tool(
        name: create_name,
        type: "Page",
        operation: :create,
        title: "Create page",
        description: "Host copy.",
        input: {
          "title" => { type: "integer", required: true, minLength: 9, description: "Host title.", example: "Hello" }
        },
        output: "the page"
      )

      listed = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == create_name }
      lookup = RecordingStudioApi.lookup(api: :public, recordable_type: "Page", operation: :create)
      title = listed.dig(:inputSchema, :properties, :title)
      contract = lookup.input_contract[:title] || lookup.input_contract["title"]

      refute listed.dig(:inputSchema, :properties).key?(:type)
      schema = RecordingStudioMcp::SchemaFromContract
      assert_equal schema.json_type(contract), title[:type]
      assert_equal schema.required?(contract), listed[:inputSchema][:required]&.include?("title")
      if schema.allow_blank?(contract)
        refute title.key?(:minLength)
      else
        assert_equal 1, title[:minLength]
      end
      assert_equal "Host title.", title[:description]
      assert_equal ["Hello"], title[:examples]
    end
  end

  def test_matching_catalog_and_lookup_enum_and_min_length_stay_aligned
    contract_field = { type: :string, required: true, enum: %w[draft published], allow_blank: false }
    catalog_property = { "type" => "string", "enum" => %w[draft published], "minLength" => 1 }

    built = RecordingStudioMcp::SchemaFromContract.property(contract_field, catalog_property: catalog_property)

    assert_equal %w[draft published], built[:enum]
    assert_equal 1, built[:minLength]
  end

  def test_unknown_type_raises_configuration_error
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "Page",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        operations: %i[show]
      )
      RecordingStudioApi.register_resource_handler("Page", :show, handler: ->(_) { { json: {} } })
      RecordingStudioMcp.register_tool(
        name: RecordingStudioMcp.tool_name("Page", :show),
        type: "Page",
        operation: :show,
        title: "Show page",
        description: "Show a page.",
        input: {},
        output: "the page"
      )
      RecordingStudioMcp.register_server(:public, api: :public) do
        include_tools RecordingStudioMcp.tool_name("Page", :show)
      end

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "unregistered type Page"
    end
  end

  def test_unknown_tool_raises_configuration_error
    with_isolated_api_configuration do
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :missing }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "unknown tool missing"
    end
  end

  def test_register_skill_stores_body_and_tools
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_skill(
        name: "page-desk",
        type: "Page",
        title: "Page desk",
        description: "Read pages.",
        body: "Use list then show.",
        tools: %w[list show describe]
      )
      RecordingStudioMcp.register_server(:public, api: :public) do
        include_tools :list, :show
        include_skills "page-desk"
      end

      skill = RecordingStudioMcp.configuration.skill("page-desk")
      listed = RecordingStudioMcp.configuration.catalogs.server_for(api: :public).skills.fetch("page-desk")

      assert_equal "Use list then show.", skill.body
      assert_equal %w[list show describe], skill.tools
      assert_equal skill.body, listed.body
      assert_equal skill.tools, listed.tools
    end
  end

  def test_delete_on_sensitive_destroy_requires_allow_sensitive
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "Page",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        writable_attributes: %i[title],
        operations: %i[show destroy],
        sensitive: [:destroy]
      )
      RecordingStudioMcp.register_type(type: "Page", description: "A page.")
      RecordingStudioApi.register_resource_handler("Page", :destroy, handler: ->(_) { { json: {} } })
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :delete }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "allow_sensitive"
    end
  end

  def test_delete_on_a_non_public_api_requires_allow_sensitive
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:operations)
      RecordingStudioApi.register_recordable_type_api(
        "Page",
        api: :operations,
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        writable_attributes: %i[title],
        operations: %i[show destroy]
      )
      RecordingStudioMcp.register_type(type: "Page", description: "A page.")
      RecordingStudioApi.register_resource_handler(
        "Page", :destroy, api: :operations, handler: ->(_) { { json: {} } }
      )
      RecordingStudioMcp.register_server(:operations, api: :operations) { include_tools :delete }

      assert_equal true, RecordingStudioApi::SensitiveFlag.default?(:operations)
      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "allow_sensitive"
    end
  end

  def test_audit_prints_sensitive_true
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "Page",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        writable_attributes: %i[title],
        operations: %i[show destroy],
        sensitive: [:destroy]
      )
      RecordingStudioMcp.register_type(type: "Page", description: "A page.")
      RecordingStudioApi.register_resource_handler("Page", :destroy, handler: ->(_) { { json: {} } })
      RecordingStudioMcp.register_server(:public, api: :public, allow_sensitive: true) { include_tools :delete }
      lines = RecordingStudioMcp.configuration.catalogs.audit!

      assert(lines.any? { |line| line.include?("tool delete sensitive=true") })
    end
  end

  def test_extra_input_key_on_generic_list_fails_boot
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_tool(
        name: "list",
        operation: :index,
        title: "List",
        description: "List records.",
        input: { "extra" => { description: "not a protocol key" } },
        output: "records"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :list }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "extra"
    end
  end

  def test_extra_input_key_on_generic_create_fails_boot
    with_isolated_api_configuration do
      register_tree_type("Page")
      RecordingStudioMcp.register_tool(
        name: "create",
        operation: :create,
        title: "Create",
        description: "Create a record.",
        input: { "sneaky" => { description: "not a protocol key" } },
        output: "the created record"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :create }

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioMcp.configuration.catalogs.build!
      end

      assert_includes error.message, "sneaky"
    end
  end

  def test_unused_register_type_is_left_off_describe
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show])
      RecordingStudioApi.register_recordable_type_api(
        "Folder",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        writable_attributes: %i[title],
        operations: %i[create]
      )
      RecordingStudioMcp.register_type(type: "Folder", description: "Unused folder.")
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :show }
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal ["Page"], catalog.type_names
      refute_includes catalog.type_schema[:enum], "Folder"
    end
  end

  def test_type_used_only_by_a_skill_shows_up_on_describe
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show])
      RecordingStudioApi.register_recordable_type_api(
        "Note",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        writable_attributes: %i[title],
        operations: %i[create]
      )
      RecordingStudioMcp.register_type(type: "Note", description: "Notes.")
      RecordingStudioMcp.register_skill(
        name: "note-desk",
        type: "Note",
        title: "Note desk",
        description: "Read notes.",
        body: "Look at Note.",
        tools: %w[describe]
      )
      RecordingStudioMcp.register_server(:public, api: :public) do
        include_tools :show
        include_skills "note-desk"
      end
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_includes catalog.type_names, "Note"
      assert_includes catalog.type_schema[:enum], "Note"
    end
  end

  def test_host_enum_in_copy_is_ignored
    with_isolated_api_configuration do
      register_tree_type("Page", writable_attributes: %i[title])
      RecordingStudioApi.register_resource_handler(
        "Page",
        :create,
        handler: ->(_) { { json: { id: "1", type: "Page" } } }
      )
      RecordingStudioMcp.register_tool(
        name: RecordingStudioMcp.tool_name("Page", :create),
        type: "Page",
        operation: :create,
        title: "Create page",
        description: "Create a page.",
        input: {
          "title" => { description: "Host title.", enum: %w[short long] }
        },
        output: "the page"
      )
      create_name = RecordingStudioMcp.tool_name("Page", :create)
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools create_name }

      listed = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == create_name }
      title = listed.dig(:inputSchema, :properties, :title)

      assert_equal "Host title.", title[:description]
      refute title.key?(:enum)
    end
  end

  def test_audit_rake_task_prints_lines
    with_isolated_api_configuration do
      register_tree_type("Page")
      require "rake"
      previous = Rake.application
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      load File.expand_path("../lib/recording_studio_mcp/tasks/audit.rake", __dir__)
      output = capture_io { Rake.application["recording_studio_mcp:audit"].invoke }.first

      assert_includes output, "server public"
      assert_includes output, "sensitive="
    ensure
      Rake.application = previous if previous
    end
  end

  def test_audit_lists_tools_and_sensitive_flags
    with_isolated_api_configuration do
      register_tree_type("Page")
      lines = RecordingStudioMcp.configuration.catalogs.audit!

      assert(lines.any? { |line| line.include?("server public") })
      assert(lines.any? { |line| line.include?("tool list sensitive=false") })
    end
  end
end
