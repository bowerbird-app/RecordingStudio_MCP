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

  def setup
    @grant = FakeGrant.new(
      api_client: FakeClient.new("public"),
      credential: nil,
      access_recording: nil,
      root_recording: nil,
      accessible_recordings: []
    )
  end

  def test_unknown_tool_is_error
    result = RecordingStudioMcp::Dispatcher.call(tool_name: "explode", arguments: {}, access_grant: @grant)

    assert_equal true, result[:isError]
    assert_includes result.dig(:content, 0, :text), "Unknown tool"
  end

  def test_list_calls_index_and_returns_json
    operation = FakeOperation.new(FakeHandler.new({ json: { records: [{ name: "Studio" }] } }))

    RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
      RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :index ? operation : nil }) do
        RecordingStudioApi.stub(:resource_name_for, "workspaces") do
          RecordingStudioApi.stub(:default_api_version, "v1") do
            result = RecordingStudioMcp::Dispatcher.call(
              tool_name: "list",
              arguments: { type: "Workspace" },
              access_grant: @grant
            )

            refute result[:isError]
            payload = JSON.parse(result.dig(:content, 0, :text))
            assert_equal "Studio", payload.dig("records", 0, "name")
          end
        end
      end
    end
  end

  def test_authorization_error_is_tool_error
    RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
      RecordingStudioApi.stub(:resource_action, ->(*) { raise RecordingStudioApi::AuthorizationError, "forbidden" }) do
        RecordingStudioApi.stub(:resource_name_for, "workspaces") do
          RecordingStudioApi.stub(:default_api_version, "v1") do
            result = RecordingStudioMcp::Dispatcher.call(
              tool_name: "list",
              arguments: { "type" => "Workspace" },
              access_grant: @grant
            )

            assert result[:isError]
            assert_equal "forbidden", result.dig(:content, 0, :text)
          end
        end
      end
    end
  end

  def test_unknown_type_is_not_found
    RecordingStudioApi.stub(:recordable_registration_for, nil) do
      RecordingStudioApi.stub(:recordable_type_for_resource, nil) do
        result = RecordingStudioMcp::Dispatcher.call(
          tool_name: "show",
          arguments: { type: "Nope", id: "1" },
          access_grant: @grant
        )

        assert result[:isError]
        assert_includes result.dig(:content, 0, :text), "Unknown API resource"
      end
    end
  end

  def test_show_loads_the_recording_in_scope
    recording = FakeRecording.new("rec-1", "Page")
    @grant.accessible_recordings = FakeRelation.new(recording)
    operation = FakeOperation.new(FakeHandler.new({ json: { title: "Getting Started" } }))

    RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
      RecordingStudioApi.stub(:resource_action, ->(name, **) { name == :show ? operation : nil }) do
        RecordingStudioApi.stub(:resource_name_for, "pages") do
          RecordingStudioApi.stub(:default_api_version, "v1") do
            result = RecordingStudioMcp::Dispatcher.call(
              tool_name: "show",
              arguments: { type: "Page", id: "rec-1" },
              access_grant: @grant
            )

            refute result[:isError]
            payload = JSON.parse(result.dig(:content, 0, :text))
            assert_equal "Getting Started", payload["title"]
          end
        end
      end
    end
  end

  def test_capability_action_requires_action
    RecordingStudioApi.stub(:recordable_registration_for, FakeRegistration.new(true)) do
      result = RecordingStudioMcp::Dispatcher.call(
        tool_name: "capability_action",
        arguments: { type: "Workspace", id: "1" },
        access_grant: @grant
      )

      assert result[:isError]
      assert_includes result.dig(:content, 0, :text), "action is required"
    end
  end
end
