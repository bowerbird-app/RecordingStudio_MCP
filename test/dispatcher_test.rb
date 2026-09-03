# frozen_string_literal: true

require "json"
require "test_helper"

class DispatcherTest < Minitest::Test
  FakeGrant = Struct.new(
    :api_client, :credential, :access_recording, :root_recording, :accessible_recordings,
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
    result = dispatch("explode", {})

    assert_equal true, result[:isError]
    assert_includes result.dig(:content, 0, :text), "Unknown tool"
    assert_includes result.dig(:content, 0, :text), "describe"
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
        RecordingStudioApi.stub(:resource_action, ->(*) { raise RecordingStudioApi::AuthorizationError, "forbidden" }) do
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
        RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :create ? FakeOperation.new(handler) : nil }) do
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

  private

  def dispatch(tool_name, arguments)
    RecordingStudioMcp::Dispatcher.call(tool_name: tool_name, arguments: arguments, access_grant: @grant)
  end
end
