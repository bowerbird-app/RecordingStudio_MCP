# frozen_string_literal: true

require "logger"
require "stringio"
require "test_helper"

class ParentHintRedis
  def initialize
    @entries = {}
  end

  def get(key)
    @entries[key]
  end

  def set(key, value, **)
    @entries[key] = value
  end
end

class AgentHintsTest < Minitest::Test
  PARENT_MISS = "Parent resource was not found in this API scope"
  SCOPE_MISS = "Resource was not found in this API scope"
  Actor = Struct.new(:id)

  def test_blank_parent_id_uses_the_workspace_when_it_is_an_allowed_parent
    with_parent_rules do
      register_parent_types
      register_create("Page", &:parent_id)
      register_create("Note", &:parent_id)
      grant = workspace_grant

      result = call_tool(grant, "create", { "type" => "Page", "title" => "Home" })
      blank = call_tool(grant, "create", { "type" => "Page", "parent_id" => "", "title" => "Home" })
      kept = call_tool(grant, "create", { "type" => "Page", "parent_id" => "folder-9", "title" => "Home" })
      page = type_clause(grant, "create", "Page")
      note = type_clause(grant, "create", "Note")

      refute result.body.dig(:result, :isError), result.body.dig(:result, :content, 0, :text)
      assert_equal "ws-1", result.body.dig(:result, :structuredContent, "parent_id")
      assert_equal "ws-1", blank.body.dig(:result, :structuredContent, "parent_id")
      assert_equal "folder-9", kept.body.dig(:result, :structuredContent, "parent_id")
      refute_includes Array(page&.dig(:then, :required)), "parent_id"
      assert_includes Array(note&.dig(:then, :required)), "parent_id"
    end
  end

  def test_parent_id_descriptions_follow_allowed_parents
    with_parent_rules do
      register_parent_types
      register_create("Page") { "ws-1" }
      register_create("Note") { "folder-1" }
      register_named_create
      grant = workspace_grant
      page = listed_tool(grant, "create_page").dig(:inputSchema, :properties, :parent_id, :description)
      note = type_clause(grant, "create", "Note").dig(:then, :properties, :parent_id, :description)
      shared = listed_tool(grant, "create").dig(:inputSchema, :properties, :parent_id, :description)

      assert_equal "Id of the Workspace this Page goes in. A blank value then uses that workspace.", page
      assert_equal "Id of the Folder this Note goes in.", note
      refute_includes shared, "A blank value then uses that workspace."
    end
  end

  def test_named_create_can_omit_parent_id_when_the_workspace_applies
    with_parent_rules do
      register_parent_types
      register_create("Page", &:parent_id)
      register_named_create
      grant = workspace_grant

      result = call_tool(grant, "create_page", { "title" => "Named" })
      schema = listed_tool(grant, "create_page").fetch(:inputSchema)

      refute result.body.dig(:result, :isError), result.body.dig(:result, :content, 0, :text)
      assert_equal "ws-1", result.body.dig(:result, :structuredContent, "parent_id")
      refute_includes schema.fetch(:required), "parent_id"
      assert schema.dig(:properties, :parent_id)
    end
  end

  def test_repeat_safe_tools_accept_an_idempotency_key
    with_parent_rules do
      seen = nil
      register_capability_actions
      register_parent_types(capability_actions: %i[add_note peek_note])
      register_create("Page") { |context| seen = context.idempotency_key }
      register_action_tool("add_note")
      register_action_tool("peek_note")
      register_named_create(publish: false)
      ensure_tree_server(:public, extra_tools: %w[create_page add_note peek_note])
      grant = workspace_grant
      described = describe_page

      create_schema = listed_tool(grant, "create_page").fetch(:inputSchema)
      add_schema = listed_tool(grant, "add_note").fetch(:inputSchema)
      peek_schema = listed_tool(grant, "peek_note").fetch(:inputSchema)
      assert create_schema.dig(:properties, :idempotency_key)
      refute_includes create_schema.fetch(:required), "idempotency_key"
      assert add_schema.dig(:properties, :idempotency_key)
      refute_includes add_schema.fetch(:required), "idempotency_key"
      refute peek_schema.fetch(:properties).key?(:idempotency_key)
      assert_equal %w[add_note create create_page], described.fetch("repeat_safe")

      captured = nil
      grant.define_singleton_method(:actor) { Actor.new("user-1") }
      result = RecordingStudioApi::Idempotency.stub(:replay, lambda { |**kwargs, &block|
        captured = kwargs[:key]
        block.call
      }) do
        call_tool(grant, "create_page", { "title" => "Once", "idempotency_key" => "page-1" })
      end

      refute result.body.dig(:result, :isError), result.body.dig(:result, :content, 0, :text)
      assert_equal "page-1", captured
      assert_equal "page-1", seen
    end
  end

  def test_action_tools_list_only_types_that_enable_the_action
    with_isolated_api_configuration do
      register_capability_actions
      register_tree_type("Page", operations: %i[index show], capability_actions: %i[add_note])
      register_tree_type("Folder", operations: %i[index show])
      register_action_tool("add_note")
      register_action_tool("orphan_note")
      ensure_tree_server(:public, extra_tools: %w[add_note orphan_note])
      names = RecordingStudioMcp::Tools.definitions.map { |tool| tool[:name] }

      assert_equal %w[Page], listed_tool(role_grant(:admin), "add_note").dig(:inputSchema, :properties, :type, :enum)
      assert_includes names, "add_note"
      refute_includes names, "orphan_note"
    end
  end

  def test_record_not_found_and_unexpected_errors_are_tool_errors
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[create])
      grant = role_grant(:admin)
      error = nil
      RecordingStudioApi.register_resource_handler("Page", :create, handler: ->(_) { raise error })
      log = StringIO.new
      missing, unexpected = Rails.stub(:logger, Logger.new(log)) do
        error = ActiveRecord::RecordNotFound.new("Couldn't find Page id=secret-row")
        first = call_tool(grant, "create", { "type" => "Page", "title" => "Home" })
        error = RuntimeError.new("bearer secret-token")
        [first, call_tool(grant, "create", { "type" => "Page", "title" => "Home" })]
      end

      assert_nil missing.body[:error]
      assert_equal true, missing.body.dig(:result, :isError)
      assert_equal SCOPE_MISS, missing.body.dig(:result, :content, 0, :text)
      refute_includes missing.body.to_json, "secret-row"
      assert_nil unexpected.body[:error]
      assert_equal true, unexpected.body.dig(:result, :isError)
      assert_equal "Internal error", unexpected.body.dig(:result, :content, 0, :text)
      refute_includes unexpected.body.to_json, "secret-token"
      assert_includes log.string, "RuntimeError"
      refute_includes log.string, "secret-token"
    end
  end

  def test_missing_parent_appends_parent_types_and_the_workspace_id
    with_parent_rules do
      register_parent_types
      register_create("Page") { raise RecordingStudioApi::NotFoundError, PARENT_MISS }
      register_create("Note") { raise RecordingStudioApi::NotFoundError, PARENT_MISS }
      grant = workspace_grant

      page = call_tool(grant, "create", { "type" => "Page", "parent_id" => "missing", "title" => "Home" })
      note = call_tool(grant, "create", { "type" => "Note", "parent_id" => "missing", "title" => "Home" })
      page_text = page.body.dig(:result, :content, 0, :text)
      note_text = note.body.dig(:result, :content, 0, :text)

      assert_includes page_text, PARENT_MISS
      assert_includes page_text, "Allowed parent types: Workspace."
      assert_includes page_text, "Workspace id: ws-1."
      assert_includes note_text, "Allowed parent types: Folder."
      refute_includes note_text, "ws-1"
    end
  end

  def test_server_chosen_parent_leaves_parent_id_out_and_ignores_a_sent_one
    with_parent_rules do
      register_parent_types
      register_create("Page", &:parent_id)
      register_create("Note", &:parent_id)
      register_server_ticket
      register_handler_slip
      register_file_note
      register_named_create_for("Ticket", "create_ticket")
      register_named_create_for("Note", "create_note")
      register_action_tool("file_note")
      ensure_tree_server(:public, extra_tools: %w[create_ticket create_note file_note])
      grant = workspace_grant

      create = listed_tool(grant, "create").fetch(:inputSchema)
      ticket = type_clause(grant, "create", "Ticket")
      note = type_clause(grant, "create", "Note")
      ticket_tool = listed_tool(grant, "create_ticket").fetch(:inputSchema)
      note_tool = listed_tool(grant, "create_note").fetch(:inputSchema)
      file_note = listed_tool(grant, "file_note").fetch(:inputSchema)
      described = describe_type("Ticket")
      fields = described.fetch("capability_actions").find { |action| action["name"] == "file_note" }
      ticket_intro = docs_intro("Ticket")
      note_intro = docs_intro("Note")

      assert create.dig(:properties, :parent_id)
      refute ticket.dig(:then, :properties).key?(:parent_id)
      refute_includes Array(ticket.dig(:then, :required)), "parent_id"
      assert_includes Array(note.dig(:then, :required)), "parent_id"
      refute ticket_tool.fetch(:properties).key?(:parent_id)
      refute_includes ticket_tool.fetch(:required), "parent_id"
      assert note_tool.dig(:properties, :parent_id)
      assert_includes note_tool.fetch(:required), "parent_id"
      refute file_note.fetch(:properties).key?(:parent_id)
      refute_includes file_note.fetch(:required), "parent_id"
      assert file_note.dig(:properties, :note)
      refute fields.dig("params", "fields").key?("parent_id")
      assert fields.dig("params", "fields", "note")
      refute_includes ticket_intro, "parent_id"
      assert_includes note_intro, "parent_id"

      sent = call_tool(grant, "create", { "type" => "Ticket", "parent_id" => "folder-9", "title" => "T" })
      blank = call_tool(grant, "create", { "type" => "Ticket", "title" => "T" })
      slip = call_tool(grant, "create", { "type" => "Slip", "parent_id" => "folder-9", "title" => "S" })
      named = call_tool(grant, "create_ticket", { "parent_id" => "folder-9", "title" => "Named" })

      [sent, blank, slip, named].each do |result|
        refute result.body.dig(:result, :isError), result.body.dig(:result, :content, 0, :text)
        assert_nil result.body.dig(:result, :structuredContent, "parent_id")
        assert_nil result.body.dig(:result, :structuredContent, "seen")
      end
    end
  end

  def test_server_chosen_parent_keeps_one_result_when_a_retry_changes_parent_id
    store = nil
    original = nil
    with_parent_rules do
      calls = 0
      register_tree_type(
        "Ticket",
        operations: %i[create],
        create_parent: :server,
        parent_resolver: ->(_context) { "ws-1" }
      )
      RecordingStudioApi.register_resource_handler("Ticket", :create, handler: lambda { |context|
        calls += 1
        { json: { parent_id: context.parent_id, calls: calls }, status: :ok }
      })
      grant = workspace_grant
      grant.define_singleton_method(:actor) { Actor.new("user-1") }
      store = RecordingStudioApi::IdempotencyStore.singleton_class
      original = RecordingStudioApi::IdempotencyStore.method(:redis)
      memory = ParentHintRedis.new
      store.define_method(:redis) { memory }
      first = call_tool(
        grant, "create",
        { "type" => "Ticket", "parent_id" => "folder-9", "title" => "T", "idempotency_key" => "ticket-1" }
      )
      second = call_tool(
        grant, "create",
        { "type" => "Ticket", "parent_id" => "other", "title" => "T", "idempotency_key" => "ticket-1" }
      )

      refute first.body.dig(:result, :isError), first.body.dig(:result, :content, 0, :text)
      refute second.body.dig(:result, :isError), second.body.dig(:result, :content, 0, :text)
      assert_equal 1, calls
      assert_equal 1, first.body.dig(:result, :structuredContent, "calls")
      assert_equal 1, second.body.dig(:result, :structuredContent, "calls")
    end
  ensure
    store.define_method(:redis, original) if store && original
  end

  def test_read_skill_returns_visible_text_and_hides_the_rest
    with_isolated_mcp_configuration do
      Dir.mktmpdir do |dir|
        register_skill_file(dir, "desk-notes", "Use the house style.\n")
        register_skill_file(dir, "hidden-notes", "Secret desk.\n", available_if: ->(*) { false })
        include_mcp_skills("desk-notes", "hidden-notes")
        grant = role_grant(:admin)

        visible = call_tool(grant, "read_skill", { "name" => "desk-notes" })
        hidden = call_tool(grant, "read_skill", { "name" => "hidden-notes" })
        unknown = call_tool(grant, "read_skill", { "name" => "missing-skill" })
        blank = call_tool(grant, "read_skill", {})
        resource = RecordingStudioMcp::Protocol.handle(
          {
            "jsonrpc" => "2.0",
            "id" => 4,
            "method" => "resources/read",
            "params" => { "uri" => "skill://desk-notes/SKILL.md" }
          },
          access_grant: grant
        )

        assert_equal "desk-notes", visible.body.dig(:result, :structuredContent, "name")
        assert_equal(
          resource.body.dig(:result, :contents, 0, :text),
          visible.body.dig(:result, :structuredContent, "text")
        )
        assert_includes visible.body.dig(:result, :structuredContent, "text"), "Use the house style."
        assert_equal "Skill was not found", hidden.body.dig(:result, :content, 0, :text)
        assert_equal hidden.body.dig(:result, :content, 0, :text), unknown.body.dig(:result, :content, 0, :text)
        assert_equal "name is required", blank.body.dig(:result, :content, 0, :text)
        assert_includes listed_tool(grant, "describe").fetch(:description), "skills via read_skill"
      end
    end
  end

  private

  def with_parent_rules(&body)
    with_isolated_api_configuration do
      RecordingStudio.stub(:root_allowed?, ->(type) { type.to_s == "Workspace" }) do
        RecordingStudio.stub(:allowed_parent_types_for, lambda { |type|
          case type.to_s
          when "Page" then ["Workspace"]
          when "Note" then ["Folder"]
          else []
          end
        }, &body)
      end
    end
  end

  def register_server_ticket
    register_tree_type(
      "Ticket",
      operations: %i[index show create],
      capability_actions: %i[file_note],
      create_parent: :server,
      parent_resolver: ->(_context) { "ws-1" }
    )
    RecordingStudioApi.register_resource_handler("Ticket", :create, handler: echo_parent_handler)
  end

  def register_handler_slip
    register_tree_type("Slip", operations: %i[create])
    RecordingStudioApi.register_resource_handler("Slip", :create, parent: :server, handler: echo_parent_handler)
  end

  def register_file_note
    RecordingStudioApi.register_capability_action(
      :file_note,
      capability: :accessible,
      creates: true,
      parent: :server,
      input_contract: {
        fields: {
          note: { type: :string, required: true },
          parent_id: { type: :string, required: true }
        }
      },
      handler: ->(_context) { { json: { ok: true } } }
    )
  end

  def register_named_create_for(type, name)
    RecordingStudioMcp.register_tool(
      name: name,
      type: type,
      operation: :create,
      title: "Create #{type}",
      description: "Create a #{type}.",
      input: {},
      output: "the record"
    )
  end

  def echo_parent_handler
    lambda do |context|
      { json: { parent_id: context.parent_id, seen: forwarded_parent(context) }, status: :ok }
    end
  end

  def forwarded_parent(context)
    values = [context.parent_id]
    [context.params, context.request_params].each do |params|
      next if params.nil?

      hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      values << (hash["parent_id"] || hash[:parent_id])
    end
    values.compact.first
  end

  def describe_type(name)
    RecordingStudioMcp::Catalog.new(api: :public).describe(name)
  end

  def docs_intro(type_name)
    spec = RecordingStudioMcp::Documentation.openapi(api: :public)
    spec.fetch("tags").find { |tag| tag["name"] == type_name }.fetch("description")
  end

  def register_create(type, &block)
    RecordingStudioApi.register_resource_handler(type, :create, handler: lambda { |context|
      { json: { parent_id: block.call(context) }, status: :ok }
    })
  end

  def register_parent_types(**page)
    register_tree_type("Page", operations: %i[index show create], **page)
    register_tree_type("Note", operations: %i[index show create])
  end

  def register_named_create(publish: true)
    RecordingStudioMcp.register_tool(
      name: "create_page",
      type: "Page",
      operation: :create,
      title: "Create page",
      description: "Create a page.",
      input: {},
      output: "the page"
    )
    ensure_tree_server(:public, extra_tools: %w[create_page]) if publish
  end

  def register_capability_actions
    register_capability(:add_note, creates: true)
    register_capability(:peek_note, creates: false)
    register_capability(:orphan_note)
  end

  def register_capability(name, creates: false)
    RecordingStudioApi.register_capability_action(
      name,
      capability: :accessible,
      creates: creates,
      handler: ->(_) { { json: { ok: true } } }
    )
  end

  def register_action_tool(name)
    RecordingStudioMcp.register_tool(
      name: name,
      action: name,
      title: name.tr("_", " ").capitalize,
      description: "Run #{name}.",
      input: {},
      output: "the result"
    )
  end

  def register_skill_file(dir, name, body, available_if: nil)
    path = File.join(dir, "#{name}.md")
    File.binwrite(path, "---\nname: #{name}\ndescription: Desk notes.\n---\n#{body}")
    RecordingStudioMcp.register_skill(name: name, path: path, available_if: available_if)
  end

  def workspace_grant
    grant = role_grant(:admin)
    grant.root_recording = Struct.new(:id, :recordable_type).new("ws-1", "Workspace")
    grant
  end

  def call_tool(grant, name, arguments)
    RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => { "name" => name, "arguments" => arguments }
      },
      access_grant: grant
    )
  end

  def listed_tool(grant, name)
    result = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
      access_grant: grant
    )
    result.body.dig(:result, :tools).find { |tool| tool[:name] == name }
  end

  def type_clause(grant, tool_name, type_name)
    listed_tool(grant, tool_name).dig(:inputSchema, :allOf)&.find do |clause|
      clause.dig(:if, :properties, :type, :const) == type_name
    end
  end

  def describe_page
    RecordingStudioMcp::Catalog.new(api: :public).describe("Page")
  end
end
