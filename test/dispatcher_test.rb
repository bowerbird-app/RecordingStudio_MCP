# frozen_string_literal: true

require "json"
require "test_helper"

class DispatcherTest < Minitest::Test
  FakeGrant = Struct.new(
    :api_client, :credential, :access_recording, :root_recording, :accessible_recordings, :actor,
    keyword_init: true
  )
  FakeClient = Struct.new(:api_key)
  FakeRegistration = Struct.new(:enabled) do
    def supports_operation?(_name)
      enabled
    end
  end
  FakeOperation = Struct.new(:handler)
  FakeAction = Struct.new(:name, :handler, :input_contract, :serializer, keyword_init: true)
  FakeHandler = Struct.new(:payload) do
    def call(_context)
      payload
    end
  end
  FakeRecording = Struct.new(:id, :recordable_type)
  FakeRelation = Struct.new(:recording) do
    def find_by(id:)
      recording if recording&.id.to_s == id.to_s
    end
  end
  FakeCatalog = Struct.new(:api) do
    def resolve_type!(name)
      raise RecordingStudioApi::NotFoundError, unknown_type_message(name) if name.to_s == "Nope"

      name.to_s
    end

    def writable_fields(_type)
      %w[title]
    end

    def unknown_action_message(action, type)
      "Unknown action #{action}. Allowed actions for #{type}: ping"
    end

    def describe(type)
      {
        "type" => type.to_s,
        "operations" => %w[index show create update],
        "writable_fields" => %w[title],
        "capability_actions" => [],
        "parent" => { "root" => false, "allowed_parent_types" => %w[Folder Workspace] }
      }
    end

    def unknown_type_message(name)
      "Unknown type #{name}. Allowed types: Folder, Page, Workspace"
    end

    def type_names
      %w[Folder Page Workspace]
    end

    def destroy_supported?
      false
    end

    def registered_endpoints
      []
    end
  end

  class DestroyCatalog < FakeCatalog
    def destroy_supported?
      true
    end

    def destroy_type_schema
      {
        type: "string",
        enum: %w[Page],
        description: "Type on this named API that allows destroy."
      }
    end
  end

  class CallTrackingScope
    def initialize(recording)
      @recording = recording
      @calls = []
    end

    attr_reader :calls

    def find_by(id:)
      @recording if @recording&.id.to_s == id.to_s
    end

    def accessible_recordings(include_trashed: false)
      @calls << { include_trashed: include_trashed }
      self
    end
  end

  def setup
    @grant = FakeGrant.new(
      api_client: FakeClient.new("public"),
      credential: nil,
      access_recording: nil,
      root_recording: nil,
      accessible_recordings: []
    )
    @catalog = FakeCatalog.new("public")
  end

  def test_unknown_tool_is_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("explode", {})

      assert_equal true, result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool"
      assert_includes result.dig(:content, 0, :text), "describe"
    end
  end

  def test_list_calls_index_and_returns_structured_content
    operation = FakeOperation.new(FakeHandler.new({ json: { records: [{ name: "Studio" }] } }))

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :index ? operation : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { type: "Workspace" })

              refute result[:isError]
              assert_equal "Studio", result.dig(:structuredContent, "records", 0, "name")
              payload = JSON.parse(result.dig(:content, 0, :text))
              assert_equal "Studio", payload.dig("records", 0, "name")
            end
          end
        end
      end
    end
  end

  def test_authorization_error_is_tool_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |*|
          raise RecordingStudioApi::AuthorizationError, "forbidden"
        }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { "type" => "Workspace" })

              assert result[:isError]
              assert_equal "forbidden", result.dig(:content, 0, :text)
            end
          end
        end
      end
    end
  end

  def test_unknown_type_lists_allowed_types
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("show", { type: "Nope", id: "1" })

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown type Nope"
      assert_includes result.dig(:content, 0, :text), "Folder"
      assert_includes result.dig(:content, 0, :text), "Page"
    end
  end

  def test_show_outside_scope_is_not_found
    @grant.accessible_recordings = FakeRelation.new(nil)
    operation = FakeOperation.new(FakeHandler.new({ json: { title: "Nope" } }))

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, nil) do
          RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :show ? operation : nil }) do
            RecordingStudioApi.stub(:resource_name_for, "pages") do
              RecordingStudioApi.stub(:default_api_version, "v1") do
                result = dispatch("show", { type: "Page", id: "outside" })

                assert result[:isError]
                assert_includes result.dig(:content, 0, :text), "Resource was not found in this API scope"
              end
            end
          end
        end
      end
    end
  end

  def test_registered_handler_show_skips_scoped_lookup
    captured = nil
    @grant.accessible_recordings = FakeRelation.new(nil)
    handler = lambda { |context|
      captured = context
      { json: { title: "Support", id: context.id }, status: :ok }
    }

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, ->(_type, action, **) { action == :show ? handler : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "support_pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("show", { type: "Page", id: "support-1" })

              refute result[:isError]
              assert_equal "Support", result.dig(:structuredContent, "title")
              assert_nil captured.recording
              assert_nil captured.parent_recording
              assert_equal "support-1", captured.id
              assert_equal @grant, captured.access_grant
              assert_nil captured.actor
            end
          end
        end
      end
    end
  end

  def test_registered_handler_list_create_update_delete_and_capability
    captured = {}
    @grant.accessible_recordings = FakeRelation.new(nil)
    resource_handler = lambda { |context|
      captured[:resource] = context
      { json: { handled: true, id: context.id, q: context.params["q"] }, status: :ok }
    }
    action = FakeAction.new(
      name: :move,
      handler: FakeHandler.new({ json: { should: "not-run" } }),
      input_contract: nil,
      serializer: nil
    )
    capability_handler = lambda { |context|
      captured[:action] = context
      { json: { moved: true, id: context.id, type: context.recordable_type }, status: :accepted }
    }

    RecordingStudioMcp::Catalog.stub(:for, DestroyCatalog.new("public")) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_name_for, "support_pages") do
          RecordingStudioApi.stub(:default_api_version, "v1") do
            RecordingStudioApi.stub(:resource_action, ->(*) { raise "builtin should not run" }) do
              {
                "list" => { type: "Page", q: "help" },
                "show" => { type: "Page", id: "support-1" },
                "create" => { type: "Page", title: "Hi", parent_id: "section-1" },
                "update" => { type: "Page", id: "support-1", title: "Hi" },
                "delete" => { type: "Page", id: "support-1" }
              }.each do |tool, args|
                RecordingStudioApi.stub(:resource_handler, ->(*) { resource_handler }) do
                  result = dispatch(tool, args)

                  refute result[:isError], tool
                  assert_equal true, result.dig(:structuredContent, "handled")
                  assert_nil captured[:resource].recording
                end
              end
            end

            RecordingStudioApi.stub(:capability_action, action) do
              RecordingStudioApi.stub(:capability_action_enabled_for?, true) do
                move_handler = ->(_type, name, **) { name == :move ? capability_handler : nil }
                RecordingStudioApi.stub(:resource_handler, move_handler) do
                  result = dispatch(
                    "capability_action",
                    { type: "Page", id: "support-1", action: "move", params: { parent_id: "section-1" } }
                  )

                  refute result[:isError]
                  assert_equal true, result.dig(:structuredContent, "moved")
                  assert_nil captured[:action].recording
                  assert_equal "support-1", captured[:action].id
                  assert_equal "Page", captured[:action].recordable_type
                  assert_equal "section-1", captured[:action].params[:parent_id]
                end
              end
            end
          end
        end
      end
    end
  end

  def test_handler_non_success_status_is_tool_error
    handler = ->(_context) { { json: { error: { message: "Support page missing" } }, status: :not_found } }

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, ->(*) { handler }) do
          RecordingStudioApi.stub(:resource_name_for, "support_pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("show", { type: "Page", id: "missing" })

              assert result[:isError]
              assert_equal "Support page missing", result.dig(:content, 0, :text)
            end
          end
        end
      end
    end
  end

  def test_delete_uses_builtin_destroy_and_includes_trashed
    recording = FakeRecording.new("rec-1", "Page")
    scope = CallTrackingScope.new(recording)
    grant = FakeGrant.new(
      api_client: FakeClient.new("public"),
      credential: nil,
      access_recording: nil,
      root_recording: nil,
      accessible_recordings: scope
    )
    grant.define_singleton_method(:accessible_recordings) do |include_trashed: false|
      scope.accessible_recordings(include_trashed: include_trashed)
    end
    operation = FakeOperation.new(FakeHandler.new({ json: { deleted: true, id: "rec-1" } }))

    RecordingStudioMcp::Catalog.stub(:for, DestroyCatalog.new("public")) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, nil) do
          RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :destroy ? operation : nil }) do
            RecordingStudioApi.stub(:resource_name_for, "pages") do
              RecordingStudioApi.stub(:default_api_version, "v1") do
                result = RecordingStudioMcp::Dispatcher.call(
                  tool_name: "delete",
                  arguments: { type: "Page", id: "rec-1" },
                  access_grant: grant
                )

                refute result[:isError]
                assert_equal true, result.dig(:structuredContent, "deleted")
                assert_includes scope.calls, { include_trashed: true }
              end
            end
          end
        end
      end
    end
  end

  def test_delete_hidden_when_destroy_is_not_supported
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("delete", { type: "Page", id: "rec-1" })

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool delete"
    end
  end

  def test_show_loads_the_recording_in_scope
    recording = FakeRecording.new("rec-1", "Page")
    @grant.accessible_recordings = FakeRelation.new(recording)
    operation = FakeOperation.new(FakeHandler.new({ json: { title: "Getting Started" } }))

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :show ? operation : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("show", { type: "Page", id: "rec-1" })

              refute result[:isError]
              assert_equal "Getting Started", result.dig(:structuredContent, "title")
            end
          end
        end
      end
    end
  end

  def test_create_rejects_attributes_envelope
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :create ? FakeOperation.new(nil) : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("create", { type: "Page", attributes: { title: "Nope" } })

              assert result[:isError]
              assert_includes result.dig(:content, 0, :text), "not inside attributes"
            end
          end
        end
      end
    end
  end

  def test_create_rejects_unknown_writable_fields
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :create ? FakeOperation.new(nil) : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("create", { type: "Page", title: "Ok", mystery: "nope" })

              assert result[:isError]
              assert_includes result.dig(:content, 0, :text), "mystery"
              assert_includes result.dig(:content, 0, :text), "title"
            end
          end
        end
      end
    end
  end

  def test_describe_returns_type_contract
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("describe", { type: "Page" })

      refute result[:isError]
      assert_equal "title", result.dig(:structuredContent, "writable_fields", 0)
    end
  end

  def test_create_passes_idempotency_key_to_api_context
    captured = nil
    handler = Class.new do
      define_method(:call) do |context|
        captured = context
        { json: { "id" => "page-1" } }
      end
    end.new

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |name, **|
          name == :create ? FakeOperation.new(handler) : nil
        }) do
          RecordingStudioApi.stub(:resource_name_for, "pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = RecordingStudioMcp::Dispatcher.call(
                tool_name: "create",
                arguments: { type: "Page", title: "Hello", idempotency_key: "create-1" },
                access_grant: @grant
              )

              refute result[:isError]
              assert_equal "create-1", captured.idempotency_key
            end
          end
        end
      end
    end
  end

  def test_capability_action_requires_action
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("capability_action", { type: "Workspace", id: "1" })

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "action is required"
    end
  end

  def test_unknown_action_lists_allowed_actions
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:capability_action, nil) do
        RecordingStudioApi.stub(:default_api_version, "v1") do
          result = dispatch("capability_action", { type: "Workspace", id: "1", action: "move" })

          assert result[:isError]
          assert_includes result.dig(:content, 0, :text), "Unknown action move"
          assert_includes result.dig(:content, 0, :text), "ping"
          refute_includes result.dig(:content, 0, :text), "for example"
        end
      end
    end
  end

  def test_endpoint_dispatch_returns_handler_payload
    captured = nil
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :echo,
        http_verb: :post,
        path: "echo/:key",
        handler: lambda { |context|
          captured = context
          { key: context.params[:key], message: context.params[:message] }
        }
      )

      result = dispatch("echo", { key: "widget", message: "hello" })

      refute result[:isError]
      assert_equal "widget", result.dig(:structuredContent, "key")
      assert_equal "hello", result.dig(:structuredContent, "message")
      assert_kind_of RecordingStudioApi::RegisteredEndpointContext, captured
      assert_equal @grant, captured.access_grant
    end
  end

  def test_endpoint_serializer_wraps_handler_result
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :shout,
        http_verb: :post,
        path: "shout",
        serializer: ->(result) { { wrapped: result } },
        handler: ->(_context) { { message: "hi" } }
      )

      result = dispatch("shout", {})

      refute result[:isError]
      assert_equal({ "message" => "hi" }, result.dig(:structuredContent, "wrapped"))
    end
  end

  def test_endpoint_input_contract_failure_is_tool_error
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :shout,
        http_verb: :post,
        path: "shout",
        input_contract: {
          fields: {
            message: { type: :string, required: true, allow_blank: false }
          }
        },
        handler: ->(_context) { { ok: true } }
      )

      result = dispatch("shout", {})

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Invalid input for endpoint shout"
    end
  end

  def test_endpoint_missing_path_token_is_tool_error
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :echo,
        http_verb: :post,
        path: "echo/:key",
        handler: ->(_context) { { ok: true } }
      )

      result = dispatch("echo", {})

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "key is required"
    end
  end

  def test_unknown_tool_on_catalog_only_host_lists_endpoint_names
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :echo,
        http_verb: :get,
        path: "echo",
        handler: ->(_context) { { ok: true } }
      )

      result = dispatch("explode", {})

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool explode"
      assert_includes result.dig(:content, 0, :text), "echo"
      refute_includes result.dig(:content, 0, :text), "describe"
    end
  end

  def test_endpoint_progress_reporter_is_passed_when_streaming
    captured = nil
    writer = Object.new
    writer.define_singleton_method(:write_json) { |_payload| nil }
    writer.define_singleton_method(:disconnected?) { false }
    context = RecordingStudioMcp::RequestContext.new(
      request_id: 3,
      protocol_version: "2025-06-18",
      access_grant: @grant,
      progress_token: "demo",
      sender: writer
    )

    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :demo_progress,
        http_verb: :get,
        path: "demo-progress",
        handler: lambda { |api_context|
          captured = api_context
          api_context.progress(current: 1, total: 1, message: "go")
          { done: true }
        }
      )

      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "demo_progress",
        arguments: {},
        access_grant: @grant,
        request_context: context
      )

      refute result[:isError]
      assert_equal true, result.dig(:structuredContent, "done")
      assert_same context, captured.progress_reporter
      assert_equal false, captured.cancelled?
    end
  end

  def test_endpoint_progress_reporter_is_nil_without_a_stream
    captured = nil

    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :demo_progress,
        http_verb: :get,
        path: "demo-progress",
        handler: lambda { |api_context|
          captured = api_context
          { done: true }
        }
      )

      result = dispatch("demo_progress", {})

      refute result[:isError]
      assert_nil captured.progress_reporter
      assert_equal false, captured.cancelled?
    end
  end

  private

  def dispatch(tool_name, arguments)
    RecordingStudioMcp::Dispatcher.call(tool_name: tool_name, arguments: arguments, access_grant: @grant)
  end
end
