# frozen_string_literal: true

require "json"
require "test_helper"

class DispatcherTest < Minitest::Test
  class PlanGateError < StandardError
    include RecordingStudio::Denial
  end

  FakeGrant = Struct.new(
    :api_client, :credential, :access_recording, :root_recording, :accessible_recordings, :actor,
    :authorized_by, :deny_authorization,
    keyword_init: true
  ) do
    def accessible_recordings(**)
      relation = self[:accessible_recordings]
      relation.respond_to?(:find_by) ? relation : FakeRelation.new(nil)
    end

    def authorize!(**)
      return unless deny_authorization

      raise RecordingStudioApi::AuthorizationError, "API access grant is not authorized for this capability"
    end

    def scope_recording
      access_recording.respond_to?(:parent_recording) ? access_recording.parent_recording : root_recording
    end

    def authorized?(**)
      !deny_authorization
    end
  end
  FakeClient = Struct.new(:api_key)
  FakeRegistration = Struct.new(:enabled) do
    def supports_operation?(_name)
      enabled
    end

    def sensitive_operation?(*)
      false
    end

    def writable_attributes
      %w[title]
    end

    def openapi
      {}
    end

    def public_name
      nil
    end

    def metric_names
      []
    end
  end
  FakeOperation = Struct.new(:handler)
  SCOPE_MISS = "Resource was not found in this API scope"
  FakeAction = Struct.new(
    :name, :handler, :input_contract, :serializer,
    :owns_scoping, :http_verb, :include_trashed, :trashed_semantics, :required_role, :creates,
    keyword_init: true
  ) do
    def owns_scoping?
      owns_scoping == true
    end

    def creates?
      creates == true
    end

    def http_verb
      self[:http_verb] || :post
    end
  end
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

    def writable_fields(*)
      %w[title]
    end

    def displayed_type_name(type)
      type.to_s
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

    def type_schema
      { type: "string", enum: type_names }
    end

    def type_schema_for(_operation)
      type_schema
    end

    def type_names_for(_operation)
      []
    end

    def destroy_type_names
      []
    end

    def registered_operations
      %i[index show create update]
    end

    def visible_operations
      registered_operations
    end

    def capability_actions?
      true
    end

    def capability_actions_advertised?
      resolved_server&.tool?("capability_action")
    end

    def registered_endpoints
      []
    end

    def list_parent_id?
      false
    end

    def parent_required?(_type)
      false
    end

    def resolved_server
      RecordingStudioMcp.configuration.catalogs.server_for(api: api)
    end
  end

  class PublicTypeCatalog < FakeCatalog
    NAMES = {
      "RecordingStudioPresskits::PressKit" => "PressKit",
      "RecordingStudioPresskits::PressCenter" => "PressCenter"
    }.freeze

    def displayed_type_name(type)
      NAMES.fetch(type.to_s, type.to_s)
    end
  end

  class DestroyCatalog < FakeCatalog
    def registered_operations
      %i[index show create update destroy]
    end

    def destroy_type_names
      %w[Page]
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
    @lookup_handler_calls = 0
    @lookup_sensitive = false
    @grant = FakeGrant.new(
      api_client: FakeClient.new("public"),
      credential: nil,
      access_recording: nil,
      root_recording: nil,
      accessible_recordings: []
    )
    @catalog = FakeCatalog.new("public")
    ensure_tree_server(:public)
  end

  def test_unknown_tool_is_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("explode", {})

      assert_equal true, result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool"
      assert_includes result.dig(:content, 0, :text), "describe"
    end
  end

  def test_tool_call_clears_authorized_by
    authorized_by = Struct.new(:id).new(41)
    client = Struct.new(:id).new("client-1")
    grant = FakeGrant.new(
      api_client: client,
      credential: nil,
      access_recording: nil,
      root_recording: nil,
      accessible_recordings: [],
      authorized_by: authorized_by
    )

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = call_as(grant, "explode", {})

      assert_equal true, result[:isError]
    end

    assert_nil RecordingStudioMcp::AuthorizedBy.current_authorized_by
    assert_nil RecordingStudioMcp::AuthorizedBy.current_client
    assert_equal 0, RecordingStudioMcp::AuthorizedBy.depth

    metadata = { "authorized_by_type" => "Spoofed" }
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudio::Hooks.run(:before_record, actor: client, metadata: metadata)
    assert_equal "Spoofed", metadata["authorized_by_type"]
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
              assert_operator @lookup_handler_calls, :>=, 1
              assert_equal "Studio", result.dig(:structuredContent, "records", 0, "name")
              payload = JSON.parse(result.dig(:content, 0, :text))
              assert_equal "Studio", payload.dig("records", 0, "name")
            end
          end
        end
      end
    end
  end

  def test_sensitive_lookup_handler_still_runs
    @lookup_sensitive = true
    operation = FakeOperation.new(FakeHandler.new({ json: { records: [{ name: "Studio" }] } }))

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :index ? operation : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { type: "Workspace" })

              refute result[:isError]
              assert_operator @lookup_handler_calls, :>=, 1
              assert_equal "Studio", result.dig(:structuredContent, "records", 0, "name")
            end
          end
        end
      end
    end
  end

  def test_tool_results_use_public_type_names
    catalog = PublicTypeCatalog.new("public")
    listed = {
      records: [
        {
          id: "4",
          type: "RecordingStudioPresskits::PressKit",
          recordable_type: "RecordingStudioPresskits::PressKit",
          section: { id: "2", type: "RecordingStudioPresskits::PressCenter" },
          field: { type: "object", recordable_type: "Nope::Missing", label: "Keep::This" },
          attachment: { type: "RecordingStudioAttachable::Attachment" },
          location: { recordable_type: "RecordingStudio::Location::Location" }
        }
      ]
    }
    operation = FakeOperation.new(FakeHandler.new({ json: listed }))

    RecordingStudioMcp::Catalog.stub(:for, catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :index ? operation : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "press_kits") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { type: "PressKit" })

              assert_public_type_names result
            end
          end
        end
      end
    end
  end

  def test_capability_action_results_use_public_type_names
    catalog = PublicTypeCatalog.new("public")
    recording = FakeRecording.new("kit-1", "PressKit")
    @grant.accessible_recordings = FakeRelation.new(recording)
    action = FakeAction.new(name: :trashable_list_trash_bin, handler: nil, input_contract: nil, serializer: nil)
    handler = lambda { |_context|
      {
        json: {
          records: [
            {
              id: "9",
              type: "RecordingStudioPresskits::PressKit",
              recordable_type: "RecordingStudioPresskits::PressKit"
            }
          ]
        },
        status: :ok
      }
    }

    RecordingStudioMcp::Catalog.stub(:for, catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:default_api_version, "v1") do
          RecordingStudioApi.stub(:capability_action, action) do
            RecordingStudioApi.stub(:capability_action_enabled_for?, true) do
              RecordingStudioApi.stub(:resource_handler, ->(*) { handler }) do
                result = dispatch(
                  "capability_action",
                  { type: "PressKit", id: "kit-1", action: "trashable_list_trash_bin" }
                )

                refute result[:isError]
                row = result.dig(:structuredContent, "records", 0)
                assert_equal "PressKit", row["type"]
                assert_equal "PressKit", row["recordable_type"]
                assert_equal "PressKit", JSON.parse(result.dig(:content, 0, :text)).dig("records", 0, "type")
              end
            end
          end
        end
      end
    end
  end

  def test_record_invalid_is_tool_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |*|
          raise ActiveRecord::RecordInvalid, invalid_record(["Title can't be blank"])
        }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { "type" => "Workspace" })

              assert result[:isError]
              assert_equal "Title can't be blank", result.dig(:content, 0, :text)
            end
          end
        end
      end
    end
  end

  def test_recording_studio_authorization_error_is_tool_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |*|
          raise RecordingStudio::AuthorizationError, "write denied"
        }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { "type" => "Workspace" })

              assert result[:isError]
              assert_equal "Not authorized", result.dig(:content, 0, :text)
            end
          end
        end
      end
    end
  end

  def test_actor_required_is_tool_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |*|
          raise RecordingStudio::ActorRequired, "actor is required for RecordingStudio writes"
        }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { "type" => "Workspace" })

              assert result[:isError]
              assert_includes result.dig(:content, 0, :text), "actor is required"
            end
          end
        end
      end
    end
  end

  def test_plan_denial_inside_an_action_is_tool_error
    error = PlanGateError.new("plan full").denial(
      code: :plan_limit,
      details: { message: "This plan includes 3 pages" }
    )
    interpreted = {
      code: "plan_limit",
      message: "This plan includes 3 pages",
      details: { message: "This plan includes 3 pages" }
    }

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(*) { raise error }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              RecordingStudioApi::BillingDenial.stub(:interpret, interpreted) do
                result = dispatch("create", { "type" => "Page", "title" => "Nope" })

                assert result[:isError]
                assert_equal "This plan includes 3 pages", result.dig(:content, 0, :text)
                assert_equal "plan_limit", result.dig(:structuredContent, "code")
              end
            end
          end
        end
      end
    end
  end

  def test_unrecognized_denial_inside_an_action_is_tool_error
    error = PlanGateError.new("blocked").denial(code: :mystery_gate, details: { message: "blocked" })

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(*) { raise error }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("create", { "type" => "Page", "title" => "Nope" })

              assert result[:isError]
              assert_equal "This action is not allowed", result.dig(:content, 0, :text)
            end
          end
        end
      end
    end
  end

  def test_invalid_parent_is_tool_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |*|
          raise RecordingStudio::InvalidParent, "Folder cannot be recorded under Page"
        }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("create", { "type" => "Folder", "parent_id" => "page-1" })

              assert result[:isError]
              assert_equal "Folder cannot be recorded under Page", result.dig(:content, 0, :text)
              refute result.key?(:structuredContent)
            end
          end
        end
      end
    end
  end

  def test_invalid_action_input_details_are_in_the_tool_error
    details = [
      {
        attribute: :unknown_field,
        message: "is unknown",
        full_message: "unknown_field is unknown",
        type: :unknown
      }
    ]

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        handler = lambda { |*|
          raise RecordingStudioApi::InvalidActionInputError.new(
            "Unknown parameters: unknown_field",
            details: details
          )
        }
        @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Workspace"))
        RecordingStudioApi.stub(:resource_handler, ->(*) { handler }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("update", { "type" => "Workspace", "id" => "1" })

              assert result[:isError]
              assert_includes result.dig(:content, 0, :text), "unknown_field"
              assert_equal(
                [
                  {
                    "attribute" => "unknown_field",
                    "message" => "is unknown",
                    "full_message" => "unknown_field is unknown",
                    "type" => "unknown"
                  }
                ],
                result.dig(:structuredContent, "details")
              )
            end
          end
        end
      end
    end
  end

  def test_standard_error_during_tools_call_is_a_generic_tool_error
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, lambda { |*|
          raise StandardError, "boom"
        }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { "type" => "Workspace" })

              assert result[:isError]
              assert_equal "Internal error", result.dig(:content, 0, :text)
              refute_includes result.dig(:content, 0, :text), "boom"
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

  def test_registered_handler_show_rejects_an_id_outside_scope
    called = false
    @grant.accessible_recordings = FakeRelation.new(nil)
    handler = lambda { |_context|
      called = true
      { json: { title: "Support" }, status: :ok }
    }

    result = dispatch_custom_show(handler, { type: "Page", id: "support-1" })

    assert_scope_miss result
    refute called
  end

  def test_registered_handler_show_passes_the_scoped_recording
    captured = nil
    recording = FakeRecording.new("support-1", "Page")
    @grant.accessible_recordings = FakeRelation.new(recording)
    handler = lambda { |context|
      captured = context
      { json: { title: "Support", id: context.recording.id }, status: :ok }
    }

    result = dispatch_custom_show(handler, { type: "Page", id: "support-1" })

    refute result[:isError]
    assert_equal "Support", result.dig(:structuredContent, "title")
    assert_same recording, captured.recording
    assert_nil captured.parent_recording
    assert_equal "support-1", captured.id
    assert_equal @grant, captured.access_grant
  end

  def test_list_passes_parent_id_to_the_api_context
    captured = nil
    handler = lambda { |context|
      captured = context
      { json: { records: [] }, status: :ok }
    }

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, ->(_type, action, **) { action == :index ? handler : nil }) do
          RecordingStudioApi.stub(:resource_name_for, "pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              result = dispatch("list", { type: "Page", parent_id: "folder-1" })

              refute result[:isError]
              assert_equal "folder-1", captured.parent_id
              assert_equal "folder-1", captured.params["parent_id"]
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
                "create" => { type: "Page", title: "Hi", parent_id: "section-1" }
              }.each do |tool, args|
                RecordingStudioApi.stub(:resource_handler, ->(*) { resource_handler }) do
                  result = dispatch(tool, args)

                  refute result[:isError], tool
                  assert_equal true, result.dig(:structuredContent, "handled")
                  assert_nil captured[:resource].recording
                  assert_nil captured[:resource].parent_recording
                end
              end

              %w[show update delete].each do |tool|
                called = false
                missing = lambda { |_context|
                  called = true
                  { json: { handled: true }, status: :ok }
                }
                RecordingStudioApi.stub(:resource_handler, ->(*) { missing }) do
                  result = dispatch(tool, { type: "Page", id: "support-1", title: "Hi" })

                  assert_scope_miss result
                  refute called, tool
                end
              end
            end

            recording = FakeRecording.new("support-1", "Page")
            @grant.accessible_recordings = FakeRelation.new(recording)
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
                  assert_same recording, captured[:action].recording
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
    @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("missing", "Page"))
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
                result = call_as(grant, "delete", { type: "Page", id: "rec-1" })

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

  def test_show_does_not_include_trashed_recordings
    recording = FakeRecording.new("rec-1", "Page")
    scope = CallTrackingScope.new(recording)
    scope.define_singleton_method(:find_by) do |id:|
      return if calls.last == { include_trashed: false }

      recording if recording.id.to_s == id.to_s
    end
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
    show = FakeOperation.new(FakeHandler.new({ json: { id: "rec-1", title: "Still here" } }))

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, nil) do
          RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :show ? show : nil }) do
            RecordingStudioApi.stub(:resource_name_for, "pages") do
              RecordingStudioApi.stub(:default_api_version, "v1") do
                result = call_as(grant, "show", { type: "Page", id: "rec-1" })

                assert result[:isError]
                assert_includes result.dig(:content, 0, :text), "Resource was not found in this API scope"
                assert_includes scope.calls, { include_trashed: false }
              end
            end
          end
        end
      end
    end
  end

  def test_create_hidden_when_no_type_supports_create
    catalog = Class.new(FakeCatalog) do
      def registered_operations
        %i[index show]
      end

      def capability_actions?
        false
      end
    end.new("public")

    RecordingStudioMcp::Catalog.stub(:for, catalog) do
      result = dispatch("create", { type: "Page", title: "Hi" })

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool create"
    end
  end

  def test_create_denied_when_type_does_not_support_it
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(false)) do
        RecordingStudioApi.stub(:resource_name_for, "pages") do
          RecordingStudioApi.stub(:default_api_version, "v1") do
            result = dispatch("create", { type: "Page", title: "Hi" })

            assert result[:isError]
            assert_includes result.dig(:content, 0, :text), "create is not enabled for Page"
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

  def test_update_rejects_immutable_fields_and_create_still_accepts_them
    with_isolated_api_configuration do
      register_tree_type(
        "Credit",
        writable_attributes: %i[name credit_id],
        immutable_fields: %i[credit_id],
        operations: %i[index show create update]
      )
      RecordingStudioApi.register_resource_handler(
        "Credit",
        :create,
        handler: ->(_context) { { json: { id: "1", name: "Ada", credit_id: "c-1" } } }
      )
      RecordingStudioApi.register_resource_handler(
        "Credit",
        :update,
        handler: ->(context) { { json: { id: context.id, name: "Ada" } } }
      )
      ensure_tree_server(:public)
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Credit"))
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      update_tool = RecordingStudioMcp::Tools.definitions.find { |tool| tool[:name] == "update" }
      update_clause = update_tool.dig(:inputSchema, :allOf).find do |clause|
        clause.dig(:if, :properties, :type, :const) == "Credit"
      end

      assert_equal %w[name], catalog.writable_fields("Credit", operation: :update)
      refute update_clause.dig(:then, :properties).key?(:credit_id)
      assert_equal %w[name], update_clause.dig(:then, :properties).keys.map(&:to_s).sort

      rejected = dispatch("update", { type: "Credit", id: "1", credit_id: "c-1", name: "Ada" })
      updated = dispatch("update", { type: "Credit", id: "1", name: "Ada" })
      created = dispatch("create", { type: "Credit", credit_id: "c-1", name: "Ada" })

      assert rejected[:isError]
      assert_includes rejected.dig(:content, 0, :text), "credit_id cannot be changed on update"
      assert_includes rejected.dig(:content, 0, :text), "Writable fields for Credit: name"
      refute_includes rejected.dig(:content, 0, :text), "name, credit_id"
      refute updated[:isError], updated.dig(:content, 0, :text)
      refute created[:isError], created.dig(:content, 0, :text)
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
              result = dispatch("create", { type: "Page", title: "Hello", idempotency_key: "create-1" })

              refute result[:isError]
              assert_equal "create-1", captured.idempotency_key
            end
          end
        end
      end
    end
  end

  def test_capability_action_array_result_wraps_records
    with_isolated_api_configuration do
      register_ping_capability
      RecordingStudioApi.register_capability_action(
        :list_followers,
        capability: :accessible,
        handler: ->(_context) { { json: [{ id: "follower-1" }, { id: "follower-2" }] } }
      )
      register_tree_type("PressCenter", capability_actions: %i[list_followers ping])
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("center-1", "PressCenter"))

      array_result = dispatch(
        "capability_action",
        { type: "PressCenter", id: "center-1", action: "list_followers" }
      )
      hash_result = dispatch("capability_action", { type: "PressCenter", id: "center-1", action: "ping" })

      refute array_result[:isError], array_result.dig(:content, 0, :text)
      assert_instance_of Hash, array_result[:structuredContent]
      assert_equal(
        [{ "id" => "follower-1" }, { "id" => "follower-2" }],
        array_result.dig(:structuredContent, "records")
      )
      assert_equal array_result[:structuredContent], JSON.parse(array_result.dig(:content, 0, :text))
      refute hash_result[:isError], hash_result.dig(:content, 0, :text)
      assert_equal true, hash_result.dig(:structuredContent, "ok")
      refute hash_result[:structuredContent].key?("records")
    end
  end

  def test_capability_action_result_includes_fields_that_need_the_grant
    with_isolated_api_configuration do
      recordable = Object.new
      recording = Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)
                        .new("note-1", "GrantFieldNote", recordable, nil, nil)
      RecordingStudioApi.register_recordable_type_api(
        "GrantFieldNote",
        serializer: lambda { |_recordable, context: nil|
          { headline: context&.access_grant ? "visible" : nil }
        },
        output_keys: %i[headline],
        operations: %i[index show],
        capability_actions: %i[stamp]
      )
      RecordingStudioApi.register_capability_action(
        :stamp,
        capability: :accessible,
        handler: ->(_context) { recording }
      )
      RecordingStudioMcp.register_type(
        type: "GrantFieldNote",
        description: "A note used to assert grant-backed fields."
      )
      ensure_tree_server(:public)
      @grant.accessible_recordings = FakeRelation.new(recording)

      result = dispatch(
        "capability_action",
        { type: "GrantFieldNote", id: "note-1", action: "stamp" }
      )

      refute result[:isError], result.dig(:content, 0, :text)
      assert_equal "visible", result.dig(:structuredContent, "headline")
    end
  end

  def test_capability_contract_names_fields_and_rules
    with_isolated_api_configuration do
      RecordingStudioApi.register_capability_action(
        :create_upload,
        capability: :attachable,
        input_contract: {
          fields: {
            filename: { type: :string, required: true },
            byte_size: { type: :integer, required: true, description: "The file size in bytes." },
            checksum: {
              type: :string,
              required: true,
              description: "MD5 checksum of the file bytes, Base64-encoded, as Active Storage expects."
            },
            kind: { type: :string, required: true, enum: %w[image file] }
          }
        },
        handler: ->(_context) { { json: { ok: true } } }
      )
      register_tree_type("Page", capability_actions: %i[create_upload])
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Page"))

      missing = dispatch(
        "capability_action",
        { type: "Page", id: "1", action: "create_upload", params: { filename: "cover.jpg" } }
      )
      enum = dispatch(
        "capability_action",
        {
          type: "Page",
          id: "1",
          action: "create_upload",
          params: { filename: "cover.jpg", byte_size: 12, checksum: "abcd", kind: "video" }
        }
      )

      assert missing[:isError]
      missing_text = missing.dig(:content, 0, :text)
      assert_includes missing_text, "byte_size is required"
      assert_includes missing_text, "checksum is required"
      assert_includes missing_text, "Base64"
      assert_includes missing_text, "MD5"
      assert enum[:isError]
      assert_includes enum.dig(:content, 0, :text), "kind must be one of: image, file"
    end
  end

  def test_capability_action_requires_action
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      result = dispatch("capability_action", { type: "Workspace", id: "1" })

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "action is required"
    end
  end

  def test_unknown_action_lists_registered_tool_names
    with_isolated_api_configuration do
      RecordingStudioApi.register_capability_action(
        :ping,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } }
      )
      register_tree_type("Page", capability_actions: %i[ping])
      RecordingStudioMcp.register_tool(
        name: "ring_bell",
        action: :ping,
        title: "Ring",
        description: "Ring the bell.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: %w[ring_bell])
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Page"))

      result = dispatch("capability_action", { type: "Page", id: "1", action: "nope" })
      text = result.dig(:content, 0, :text)

      assert result[:isError]
      assert_includes text, "Unknown action nope"
      assert_includes text, "Allowed tools for Page: ring_bell"
      refute_includes text, "ping"
    end
  end

  def test_contract_failure_names_the_invoked_tool
    with_isolated_api_configuration do
      RecordingStudioApi.register_capability_action(
        :attach,
        capability: :accessible,
        input_contract: { fields: { note: { type: :string, required: true } } },
        handler: ->(_context) { { json: { ok: true } } }
      )
      register_tree_type("Page", capability_actions: %i[attach])
      RecordingStudioMcp.register_tool(
        name: "attach",
        action: :attach,
        title: "Attach",
        description: "Attach a file.",
        input: {},
        output: "ok"
      )
      ensure_tree_server(:public, extra_tools: %w[attach])
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Page"))

      result = dispatch("attach", { type: "Page", id: "1" })
      text = result.dig(:content, 0, :text)

      assert result[:isError]
      assert_includes text, "Invalid input for attach"
      refute_includes text, "Invalid input for action"
    end
  end

  def test_deadlock_is_a_retryable_busy_error
    assert_retryable_busy ActiveRecord::Deadlocked.new("token-secret-payload")
  end

  def test_lock_wait_timeout_is_a_retryable_busy_error
    skip "LockWaitTimeout is not defined" unless defined?(ActiveRecord::LockWaitTimeout)

    assert_retryable_busy ActiveRecord::LockWaitTimeout.new("token-secret-payload")
  end

  def test_lock_timeout_cancel_is_a_retryable_busy_error
    error = ActiveRecord::QueryCanceled.new("canceling statement due to lock timeout token-secret-payload")

    assert_retryable_busy error
  end

  def test_statement_timeout_stays_an_internal_error
    error = ActiveRecord::QueryCanceled.new("canceling statement due to statement timeout token-secret-payload")
    text, log = captured_tool_failure(error)

    assert_equal "Internal error", text
    assert_includes log, "QueryCanceled"
    refute_includes log, "token-secret-payload"
  end

  def test_type_mismatch_names_a_type_inside_this_api
    recording = FakeRecording.new("rec-1", "Page")
    @grant.accessible_recordings = FakeRelation.new(recording)

    text = type_mismatch_text

    assert_includes text, "Resource type does not match Workspace"
    assert_includes text, "This id is a Page"
    assert_includes text, "content_id"
  end

  def test_type_mismatch_outside_this_api_stays_not_found
    recording = FakeRecording.new("rec-1", "HiddenNote")
    @grant.accessible_recordings = FakeRelation.new(recording)

    text = type_mismatch_text

    assert_equal SCOPE_MISS, text
    refute_includes text, "HiddenNote"
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
      mcp_endpoint(
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
      mcp_endpoint(
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
      register_mcp_endpoint_tool(
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
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :shout }

      result = dispatch("shout", {})

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Invalid input for endpoint shout"
    end
  end

  def test_endpoint_contract_errors_are_named_in_the_tool_message
    with_isolated_api_configuration do
      register_mcp_endpoint_tool(
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
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :shout }

      result = dispatch("shout", { foo: "bar" })

      assert result[:isError]
      text = result.dig(:content, 0, :text)
      assert_includes text, "Invalid input for endpoint shout"
      assert_includes text, "foo"
    end
  end

  def test_endpoint_missing_path_token_is_tool_error
    with_isolated_api_configuration do
      register_mcp_endpoint_tool(
        :echo,
        http_verb: :post,
        path: "echo/:key",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :echo }

      result = dispatch("echo", {})

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "key is required"
    end
  end

  def test_blank_parent_id_on_an_endpoint_reaches_the_api_message
    seen = nil
    with_isolated_api_configuration do
      mcp_endpoint(
        :create_kit,
        http_verb: :post,
        path: "kits/:parent_id",
        handler: lambda { |context|
          seen = context.params[:parent_id]
          raise RecordingStudioApi::InvalidActionInputError, "parent_id is required for PressKit"
        }
      )

      result = dispatch("create_kit", { parent_id: "" })
      text = result.dig(:content, 0, :text)

      assert result[:isError]
      assert_equal "", seen
      assert_includes text, "parent_id is required for PressKit"
      refute_equal "parent_id is required", text
    end
  end

  def test_unknown_tool_on_catalog_only_host_lists_endpoint_names
    with_isolated_api_configuration do
      register_mcp_endpoint_tool(
        :echo,
        http_verb: :get,
        path: "echo",
        handler: ->(_context) { { ok: true } }
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools :echo }

      result = dispatch("explode", {})

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "Unknown tool explode"
      assert_includes result.dig(:content, 0, :text), "echo"
      assert_includes result.dig(:content, 0, :text), "describe"
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
      mcp_endpoint(
        :demo_progress,
        http_verb: :get,
        path: "demo-progress",
        handler: lambda { |api_context|
          captured = api_context
          api_context.progress(current: 1, total: 1, message: "go")
          { done: true }
        }
      )

      result = dispatch("demo_progress", {}, request_context: context)

      refute result[:isError]
      assert_equal true, result.dig(:structuredContent, "done")
      assert_same context, captured.progress_reporter
      assert_equal false, captured.cancelled?
    end
  end

  def test_endpoint_progress_reporter_is_nil_without_a_stream
    captured = nil

    with_isolated_api_configuration do
      mcp_endpoint(
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

  def test_named_show_and_delete_forward_id
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show destroy])
      shown = nil
      deleted = nil
      RecordingStudioApi.register_resource_handler("Page", :show, handler: lambda { |context|
        shown = context.id
        { json: { id: context.id, type: "Page" } }
      })
      RecordingStudioApi.register_resource_handler("Page", :destroy, handler: lambda { |context|
        deleted = context.id
        { json: { deleted: true, id: context.id } }
      })
      show_page = RecordingStudioMcp.tool_name("Page", :show)
      delete_page = RecordingStudioMcp.tool_name("Page", :destroy)
      RecordingStudioMcp.register_tool(
        name: show_page,
        type: "Page",
        operation: :show,
        title: "Show page",
        description: "Show a page.",
        input: {},
        output: "the page"
      )
      RecordingStudioMcp.register_tool(
        name: delete_page,
        type: "Page",
        operation: :destroy,
        title: "Delete page",
        description: "Delete a page.",
        input: {},
        output: "the delete result"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools show_page, delete_page }
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("rec-1", "Page"))

      shown_result = dispatch(show_page, { id: "rec-1" })
      deleted_result = dispatch(delete_page, { id: "rec-1" })
      missing_show = dispatch(show_page, {})
      missing_delete = dispatch(delete_page, {})

      refute shown_result[:isError], shown_result.dig(:content, 0, :text)
      assert_equal "rec-1", shown
      refute deleted_result[:isError], deleted_result.dig(:content, 0, :text)
      assert_equal "rec-1", deleted
      assert missing_show[:isError]
      assert_equal "id is required", missing_show.dig(:content, 0, :text)
      assert missing_delete[:isError]
      assert_equal "id is required", missing_delete.dig(:content, 0, :text)
    end
  end

  def test_typeless_named_action_dispatch_uses_args_type
    with_isolated_api_configuration do
      captured = nil
      RecordingStudioApi.register_capability_action(
        :create_upload,
        capability: :attachable,
        input_contract: {
          fields: {
            filename: { type: :string, required: true },
            byte_size: { type: :integer, required: true }
          }
        },
        handler: lambda { |context|
          captured = context
          { json: { ok: true, filename: context.params[:filename] } }
        }
      )
      register_tree_type("Page", capability_actions: %i[create_upload])
      RecordingStudioMcp.register_tool(
        name: "create_upload",
        action: :create_upload,
        title: "Create upload",
        description: "Create an upload on the host type passed in args.",
        input: {},
        output: "the upload"
      )
      ensure_tree_server(:public, extra_tools: %w[create_upload])
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Page"))

      result = dispatch("create_upload", { type: "Page", id: "1", filename: "cover.jpg", byte_size: 12 })

      refute result[:isError], result.dig(:content, 0, :text)
      assert_equal "cover.jpg", result.dig(:structuredContent, "filename")
      assert_equal "cover.jpg", captured.params[:filename]
      assert_equal 12, captured.params[:byte_size]
      refute captured.params.key?(:type)
      refute captured.params.key?(:id)
      refute captured.params.key?(:action)
    end
  end

  def test_client_sent_type_and_action_are_ignored_for_registered_tools
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show], capability_actions: %i[inspect])
      register_tree_type("Folder", operations: %i[show])
      RecordingStudioApi.register_capability_action(
        :inspect,
        capability: :accessible,
        handler: ->(_context) { { json: { action: "inspect" } } }
      )
      shown = nil
      RecordingStudioApi.register_resource_handler("Page", :show, handler: lambda { |context|
        shown = context.recordable_type
        { json: { id: "1", type: context.recordable_type } }
      })
      RecordingStudioApi.register_resource_handler("Folder", :show, handler: lambda { |_context|
        { json: { id: "2", type: "Folder" } }
      })
      show_page = RecordingStudioMcp.tool_name("Page", :show)
      inspect_page = RecordingStudioMcp.tool_name("Page", :inspect)
      RecordingStudioMcp.register_tool(
        name: show_page,
        type: "Page",
        operation: :show,
        title: "Show page",
        description: "Show a page.",
        input: {},
        output: "the page"
      )
      RecordingStudioMcp.register_tool(
        name: inspect_page,
        type: "Page",
        action: :inspect,
        title: "Inspect page",
        description: "Inspect a page.",
        input: {},
        output: "the result"
      )
      RecordingStudioMcp.register_server(:public, api: :public) { include_tools show_page, inspect_page }
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Page"))

      shown_result = dispatch(show_page, { type: "Folder", id: "1" })
      inspect_result = dispatch(inspect_page, { type: "Folder", id: "1", action: "missing" })

      refute shown_result[:isError]
      assert_equal "Page", shown
      assert_equal "Page", shown_result.dig(:structuredContent, "type")
      refute inspect_result[:isError]
      assert_equal "inspect", inspect_result.dig(:structuredContent, "action")
    end
  end

  def test_show_only_rejects_list
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[show])
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("1", "Page"))
      RecordingStudioApi.register_resource_handler("Page", :show, handler: ->(_) { { json: { id: "1" } } })
      listed = dispatch("list", { type: "Page" })
      shown = dispatch("show", { type: "Page", id: "1" })

      assert listed[:isError]
      assert_includes listed.dig(:content, 0, :text), "Unknown tool list"
      refute shown[:isError]
    end
  end

  def test_index_only_rejects_show
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index])
      RecordingStudioApi.register_resource_handler("Page", :index, handler: ->(_) { { json: { records: [] } } })
      hidden = dispatch("show", { type: "Page", id: "1" })
      indexed = dispatch("list", { type: "Page" })

      assert hidden[:isError]
      assert_includes hidden.dig(:content, 0, :text), "Unknown tool show"
      refute indexed[:isError]
    end
  end

  def test_list_rejects_bad_filter_and_limit
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index])

      nested = dispatch("list", { type: "Page", filter: { name: { nested: "x" } } })
      listed = dispatch("list", { type: "Page", filter: ["name"] })
      limited = dispatch("list", { type: "Page", limit: { n: 1 } })
      arguments = dispatch("list", [1])

      assert nested[:isError]
      assert_includes nested.dig(:content, 0, :text), "Invalid filter"
      refute_includes nested.dig(:content, 0, :text), "pagination"
      assert listed[:isError]
      assert_includes listed.dig(:content, 0, :text), "filter must be an object"
      assert limited[:isError]
      assert_includes limited.dig(:content, 0, :text), "limit must be a number"
      assert arguments[:isError]
      assert_includes arguments.dig(:content, 0, :text), "arguments must be an object"
    end
  end

  def test_view_admin_and_deleted_grants_filter_calls
    with_isolated_api_configuration do
      register_tree_type("Page", operations: %i[index show create])
      RecordingStudioApi.register_resource_handler("Page", :index, handler: ->(_) { { json: { records: [] } } })
      RecordingStudioApi.register_resource_handler("Page", :create, handler: ->(_) { { json: { id: "1" } } })

      view = role_grant(:view)
      admin = role_grant(:admin)
      deleted = role_grant(nil)

      view_create = call_as(view, "create", { type: "Page" })
      view_list = call_as(view, "list", { type: "Page" })
      admin_create = call_as(admin, "create", { type: "Page", title: "Hi", parent_id: "workspace-1" })
      deleted_list = call_as(deleted, "list", { type: "Page" })

      assert view_create[:isError]
      assert_includes view_create.dig(:content, 0, :text), "Unknown tool"
      refute view_list[:isError]
      refute admin_create[:isError]
      assert deleted_list[:isError]
      assert_includes deleted_list.dig(:content, 0, :text), "Unknown tool"
    end
  end

  def test_custom_handlers_hide_guard_messages_and_skip_the_handler
    recording = FakeRecording.new("page-1", "Page")
    folder = FakeRecording.new("folder-1", "Folder")
    called = false
    handler = lambda { |_context|
      called = true
      { json: { ok: true }, status: :ok }
    }
    action = FakeAction.new(name: :move, handler: FakeHandler.new({ json: { builtin: true } }), required_role: :edit)

    [
      ["show", { type: "Page", id: "" }, FakeRelation.new(recording)],
      ["show", { type: "Page" }, FakeRelation.new(recording)]
    ].each do |tool, args, relation|
      called = false
      @grant.accessible_recordings = relation
      result = dispatch_custom_show(handler, args, tool: tool)

      assert result[:isError], tool
      assert_equal "id is required", result.dig(:content, 0, :text)
      refute called, tool
    end

    [
      ["show", { type: "Page", id: "missing" }, FakeRelation.new(nil)],
      ["update", { type: "Page", id: "page-1", title: "Hi" }, FakeRelation.new(recording)]
    ].each do |tool, args, relation|
      called = false
      @grant.accessible_recordings = relation
      @grant.deny_authorization = tool == "update"
      result = dispatch_custom_show(handler, args, tool: tool)

      assert_scope_miss result
      refute called, tool
    end

    called = false
    @grant.deny_authorization = false
    @grant.accessible_recordings = FakeRelation.new(folder)
    wrong_type = dispatch_custom_show(handler, { type: "Page", id: "folder-1" })
    wrong_text = wrong_type.dig(:content, 0, :text)

    assert wrong_type[:isError]
    assert_includes wrong_text, "This id is a Folder."
    refute_equal SCOPE_MISS, wrong_text
    refute called

    called = false
    @grant.deny_authorization = true
    @grant.accessible_recordings = FakeRelation.new(recording)
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:capability_action, action) do
          RecordingStudioApi.stub(:capability_action_enabled_for?, true) do
            RecordingStudioApi.stub(:resource_handler, ->(_type, name, **) { name == :move ? handler : nil }) do
              RecordingStudioApi.stub(:resource_name_for, "pages") do
                RecordingStudioApi.stub(:default_api_version, "v1") do
                  result = dispatch(
                    "capability_action",
                    { type: "Page", id: "page-1", action: "move" }
                  )

                  assert_scope_miss result
                  refute called
                end
              end
            end
          end
        end
      end
    end
  end

  def test_owns_scoping_reads_keep_recording_nil
    captured = nil
    @grant.accessible_recordings = FakeRelation.new(nil)
    handler = lambda { |context|
      captured = context
      { json: { open: true }, status: :ok }
    }
    registration = RecordingStudioApi::ResourceHandlerRegistration.new(
      handler: handler,
      include_trashed: false,
      owns_scoping: true,
      trashed_semantics: nil,
      creates: false
    )
    action = FakeAction.new(
      name: :inspect,
      handler: FakeHandler.new({ json: { builtin: true } }),
      http_verb: :get,
      required_role: :view,
      owns_scoping: true
    )

    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler_registration, ->(*) { registration }) do
          RecordingStudioApi.stub(:resource_handler, ->(_type, name, **) { name == :show ? handler : nil }) do
            RecordingStudioApi.stub(:resource_name_for, "pages") do
              RecordingStudioApi.stub(:default_api_version, "v1") do
                result = dispatch("show", { type: "Page", id: "outside" })

                refute result[:isError]
                assert_equal true, result.dig(:structuredContent, "open")
                assert_nil captured.recording
                assert_nil captured.parent_recording
              end
            end
          end
        end
      end
    end

    captured = nil
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:capability_action, action) do
          RecordingStudioApi.stub(:capability_action_enabled_for?, true) do
            RecordingStudioApi.stub(:resource_handler, ->(_type, name, **) { name == :inspect ? handler : nil }) do
              RecordingStudioApi.stub(:resource_name_for, "pages") do
                RecordingStudioApi.stub(:default_api_version, "v1") do
                  result = dispatch(
                    "capability_action",
                    { type: "Page", id: "outside", action: "inspect" }
                  )

                  refute result[:isError]
                  assert_nil captured.recording
                end
              end
            end
          end
        end
      end
    end
  end

  def test_scoped_endpoint_hides_misses_and_unscoped_paths_stay_nil
    called = false
    recording = FakeRecording.new("page-1", "Page")
    handler = lambda { |context|
      called = true
      { seen: context.recording&.id }
    }

    with_isolated_api_configuration do
      mcp_endpoint(
        :guard_page,
        http_verb: :post,
        path: "guard-page/:id",
        recordable_type: "Page",
        handler: handler
      )
      mcp_endpoint(
        :guard_open,
        http_verb: :post,
        path: "guard-open/:id",
        scope_id: false,
        required_role: :view,
        handler: handler
      )

      @grant.accessible_recordings = FakeRelation.new(nil)
      missing = dispatch("guard_page", { id: "page-1" })
      blank = dispatch("guard_page", { id: "" })
      omitted = dispatch("guard_page", {})

      assert_scope_miss missing
      assert_scope_miss blank
      assert_scope_miss omitted
      refute called

      @grant.accessible_recordings = FakeRelation.new(recording)
      @grant.deny_authorization = true
      denied = dispatch("guard_page", { id: "page-1" })
      assert_scope_miss denied
      refute called

      @grant.deny_authorization = false
      @grant.accessible_recordings = FakeRelation.new(FakeRecording.new("page-1", "Folder"))
      wrong_type = dispatch("guard_page", { id: "page-1" })
      assert_scope_miss wrong_type
      refute called

      @grant.accessible_recordings = FakeRelation.new(recording)
      found = dispatch("guard_page", { id: "page-1" })
      refute found[:isError]
      assert_equal "page-1", found.dig(:structuredContent, "seen")

      called = false
      @grant.accessible_recordings = FakeRelation.new(nil)
      open = dispatch("guard_open", { id: "outside" })
      refute open[:isError]
      assert_nil open.dig(:structuredContent, "seen")
      assert called
    end
  end

  private

  def assert_scope_miss(result)
    assert result[:isError]
    assert_equal SCOPE_MISS, result.dig(:content, 0, :text)
    refute_includes result.dig(:content, 0, :text), "does not match"
    refute_includes result.dig(:content, 0, :text), "authorized"
  end

  def dispatch_custom_show(handler, args, tool: "show")
    RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_handler, ->(*) { handler }) do
          RecordingStudioApi.stub(:resource_name_for, "pages") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              dispatch(tool, args)
            end
          end
        end
      end
    end
  end

  def invalid_record(messages)
    errors = Object.new
    errors.define_singleton_method(:full_messages) { messages }
    record = Object.new
    record.define_singleton_method(:errors) { errors }
    record.define_singleton_method(:class) do
      klass = Class.new
      klass.define_singleton_method(:i18n_scope) { :activerecord }
      klass
    end
    record
  end

  def assert_public_type_names(result)
    refute result[:isError]
    row = result.dig(:structuredContent, "records", 0)
    assert_equal "PressKit", row["type"]
    assert_equal "PressKit", row["recordable_type"]
    assert_equal "PressCenter", row.dig("section", "type")
    assert_equal "Missing", row.dig("field", "recordable_type")
    assert_equal "object", row.dig("field", "type")
    assert_equal "Keep::This", row.dig("field", "label")
    assert_equal "Attachment", row.dig("attachment", "type")
    assert_equal "Location", row.dig("location", "recordable_type")
    assert_equal row, JSON.parse(result.dig(:content, 0, :text)).dig("records", 0)
  end

  def mcp_endpoint(name, **)
    register_mcp_endpoint_tool(name, **)
    existing = Array(RecordingStudioMcp.configuration.servers["public"]&.included_tools).map(&:name)
    extras = (existing - RecordingStudioMcp::Catalogs::GENERIC_NAMES) + [name.to_s]
    ensure_tree_server(:public, extra_tools: extras)
  end

  def assert_retryable_busy(error)
    text, log = captured_tool_failure(error)

    assert_equal "Another change to this item is in progress. Try again.", text
    assert_includes log, error.class.name
    refute_includes log, "token-secret-payload"
  end

  def captured_tool_failure(error)
    log = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(log)
    result = RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(*) { raise error }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              dispatch("list", { "type" => "Workspace" })
            end
          end
        end
      end
    end
    [result.dig(:content, 0, :text), log.string]
  ensure
    Rails.logger = previous if previous
  end

  def type_mismatch_text
    operation = FakeOperation.new(FakeHandler.new({ json: { title: "Wrong type" } }))
    result = RecordingStudioMcp::Catalog.stub(:for, @catalog) do
      RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
        RecordingStudioApi.stub(:resource_action, ->(*) { operation }) do
          RecordingStudioApi.stub(:resource_name_for, "workspaces") do
            RecordingStudioApi.stub(:default_api_version, "v1") do
              dispatch("show", { type: "Workspace", id: "rec-1" })
            end
          end
        end
      end
    end
    result.dig(:content, 0, :text)
  end

  def dispatch(tool_name, arguments, request_context: nil)
    call_as(@grant, tool_name, arguments, request_context: request_context)
  end

  def call_as(grant, tool_name, arguments, request_context: nil)
    RecordingStudioApi::Lookup.stub(:call, method(:stubbed_lookup)) do
      RecordingStudioMcp::Dispatcher.call(
        tool_name: tool_name,
        arguments: arguments,
        access_grant: grant,
        request_context: request_context
      )
    end
  end

  def stubbed_lookup(**kwargs)
    _custom_handler, handler = stubbed_lookup_handler(
      kwargs[:api] || :public,
      kwargs[:recordable_type],
      kwargs[:operation],
      kwargs[:action],
      kwargs[:endpoint]
    )
    return if handler.nil?

    RecordingStudioApi::Lookup::Result.new(
      handler: counting_lookup_handler(handler),
      input_contract: {},
      output_schema: {},
      sensitive: @lookup_sensitive,
      apis: [kwargs[:api] || :public]
    )
  end

  def counting_lookup_handler(handler)
    inner = handler
    wrapper = lambda { |context|
      @lookup_handler_calls += 1
      inner.call(context)
    }
    wrapper.define_singleton_method(:==) { |other| equal?(other) || inner == other }
    wrapper
  end

  def stubbed_lookup_handler(api, recordable_type, operation, action, endpoint)
    if operation
      custom = RecordingStudioApi.resource_handler(recordable_type, operation, api: api)
      [!custom.nil?, custom || stubbed_resource_action_handler(api, operation)]
    elsif action
      custom = RecordingStudioApi.resource_handler(recordable_type, action, api: api)
      [!custom.nil?, custom || RecordingStudioApi.capability_action(action, api: api)&.handler]
    elsif endpoint
      [false, RecordingStudioApi.registered_endpoint(endpoint, api: api)&.handler]
    end
  end

  def stubbed_resource_action_handler(api, operation)
    registered = RecordingStudioApi.resource_action(operation, api: api)
    return unless registered

    registered.handler || FakeHandler.new({ json: {} })
  end
end
