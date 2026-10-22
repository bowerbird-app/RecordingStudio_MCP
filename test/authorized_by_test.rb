# frozen_string_literal: true

require "test_helper"

class AuthorizedByTest < Minitest::Test
  Person = Struct.new(:id)
  Client = Struct.new(:id)
  Authorization = Struct.new(:manager_actor)
  Credential = Struct.new(:oauth_authorization)
  Grant = Struct.new(:credential, :api_client)

  def setup
    @human = Person.new(41)
    @client = Client.new("client-1")
    @grant = Grant.new(Credential.new(Authorization.new(@human)), @client)
  end

  def teardown
    RecordingStudioMcp::AuthorizedBy.leave while RecordingStudioMcp::AuthorizedBy.depth.positive?
  end

  def test_api_contexts_do_not_take_an_authorized_by_keyword
    [
      RecordingStudioApi::ResourceOperationContext,
      RecordingStudioApi::ActionContext,
      RecordingStudioApi::RegisteredEndpointContext
    ].each do |context_class|
      names = context_class.instance_method(:initialize).parameters.filter_map do |type, name|
        name if %i[key keyreq].include?(type)
      end

      refute_includes names, :authorized_by
      refute_includes names, :oauth_authorization
    end
  end

  def test_tool_call_builders_do_not_pass_authorizing_keywords
    root = File.expand_path("..", __dir__)
    %w[
      lib/recording_studio_mcp/authorized_by.rb
      lib/recording_studio_mcp/dispatcher.rb
      lib/recording_studio_mcp/catalog_metric_tools/discovery.rb
      lib/recording_studio_mcp/catalog_metric_tools/execution.rb
      lib/recording_studio_mcp/recordable_metric_tools/execution.rb
    ].each do |path|
      source = File.read(File.join(root, path))

      refute_includes source, "context_keywords"
      refute_includes source, "authorizing_keywords"
    end
  end

  def test_api_credential_without_an_authorization_has_no_human
    grant = Grant.new(Object.new, Client.new("api-client"))

    assert_nil RecordingStudioMcp::AuthorizedBy.human_for(grant)
    assert_equal grant.api_client, RecordingStudioMcp::AuthorizedBy.client_for(grant)
  end

  def test_record_hook_stamps_the_authorizing_human_without_touching_the_actor
    metadata = { api_action: "move" }
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    RecordingStudio::Hooks.run(
      :before_record,
      action: "updated",
      actor: @client,
      impersonator: nil,
      metadata: metadata
    )

    assert_equal "move", metadata[:api_action]
    assert_equal "AuthorizedByTest::Person", metadata[:authorized_by_type]
    assert_equal 41, metadata[:authorized_by_id]
    assert_same 41, metadata[:authorized_by_id]
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_record_hook_overwrites_client_supplied_authorized_by_keys
    [
      { "authorized_by_type" => "Kept", "authorized_by_id" => "kept-id" },
      { authorized_by_type: "Kept", authorized_by_id: "kept-id" },
      { "authorized_by_type" => "Kept", authorized_by_id: "kept-id" },
      { authorized_by_type: "Kept", "authorized_by_id" => "kept-id" },
      { "authorized_by_type" => "Only type" },
      { authorized_by_id: "only-id" }
    ].each do |metadata|
      RecordingStudioMcp::AuthorizedBy.install!
      RecordingStudioMcp::AuthorizedBy.enter(@grant)
      RecordingStudio::Hooks.run(:before_record, actor: @client, metadata: metadata)

      assert_equal "AuthorizedByTest::Person", metadata[:authorized_by_type]
      assert_equal 41, metadata[:authorized_by_id]
      refute metadata.key?("authorized_by_type")
      refute metadata.key?("authorized_by_id")
    ensure
      RecordingStudioMcp::AuthorizedBy.leave
    end
  end

  def test_record_hook_leaves_other_actors_on_the_thread_alone
    metadata = { "authorized_by_type" => "Other", "authorized_by_id" => "other-id", note: "stay" }
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    RecordingStudio::Hooks.run(:before_record, actor: Client.new("someone-else"), metadata: metadata)

    assert_equal "Other", metadata["authorized_by_type"]
    assert_equal "other-id", metadata["authorized_by_id"]
    assert_equal "stay", metadata[:note]
    refute metadata.key?(:authorized_by_type)
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_record_hook_stamps_a_reloaded_oauth_client
    metadata = {}
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    RecordingStudio::Hooks.run(:before_record, actor: Client.new(@client.id), metadata: metadata)

    assert_equal 41, metadata[:authorized_by_id]
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_record_hook_is_a_no_op_outside_a_tool_call
    metadata = {}
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudio::Hooks.run(:before_record, actor: @client, metadata: metadata)

    assert_equal({}, metadata)
  end

  def test_leave_restores_the_previous_human_and_stops_stamping
    outer_human = Person.new(7)
    outer_client = Client.new("outer")
    outer = Grant.new(Credential.new(Authorization.new(outer_human)), outer_client)
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudioMcp::AuthorizedBy.enter(outer)
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    assert_equal @human, RecordingStudioMcp::AuthorizedBy.current_human

    RecordingStudioMcp::AuthorizedBy.leave
    assert_equal outer_human, RecordingStudioMcp::AuthorizedBy.current_human
    assert_equal outer_client, RecordingStudioMcp::AuthorizedBy.current_client

    metadata = {}
    RecordingStudio::Hooks.run(:before_record, actor: @client, metadata: metadata)
    assert_equal({}, metadata)

    outer_metadata = {}
    RecordingStudio::Hooks.run(:before_record, actor: outer_client, metadata: outer_metadata)
    assert_equal 7, outer_metadata[:authorized_by_id]
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_client_credentials_tool_call_does_not_stamp
    grant = Grant.new(Object.new, Client.new("api-client"))
    RecordingStudioMcp::AuthorizedBy.install!
    [
      { "authorized_by_type" => "Spoofed", "authorized_by_id" => "spoof", note: "stay" },
      { authorized_by_type: "Spoofed", authorized_by_id: 1, note: "stay" },
      { "authorized_by_type" => "Only type", note: "stay" },
      { authorized_by_id: "only-id", note: "stay" }
    ].each do |metadata|
      RecordingStudioMcp::AuthorizedBy.enter(grant)
      RecordingStudio::Hooks.run(:before_record, actor: grant.api_client, metadata: metadata)

      refute metadata.key?("authorized_by_type")
      refute metadata.key?(:authorized_by_type)
      refute metadata.key?("authorized_by_id")
      refute metadata.key?(:authorized_by_id)
      assert_equal "stay", metadata[:note]
    ensure
      RecordingStudioMcp::AuthorizedBy.leave
    end

    other = { "authorized_by_type" => "Other", authorized_by_id: "other-id" }
    RecordingStudioMcp::AuthorizedBy.enter(grant)
    RecordingStudio::Hooks.run(:before_record, actor: Client.new("someone-else"), metadata: other)
    assert_equal "Other", other["authorized_by_type"]
    assert_equal "other-id", other[:authorized_by_id]
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_installed_api_resolves_authorized_by_from_the_grant
    unless access_grant_resolves_authorized_by?
      skip "API #{RecordingStudioApi::VERSION} has no AccessGrant#authorized_by; CI job api-016 runs the suite on API 0.16"
    end

    credential = Credential.new(Authorization.new(@human))
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: @client,
      credential: credential,
      access_recording: nil
    )
    context = RecordingStudioApi::ActionContext.new(
      recording: nil,
      api_client: @client,
      credential: credential,
      access_recording: nil,
      access_grant: grant,
      root_recording: nil,
      params: {}
    )

    assert_equal @human, grant.authorized_by
    assert_equal @human, context.authorized_by
    assert_equal 41, context.with_authorized_by[:authorized_by_id]
  end

  private

  def access_grant_resolves_authorized_by?
    RecordingStudioApi::AccessGrant.instance_method(:initialize).parameters.any? do |_type, name|
      name == :authorized_by
    end
  end
end
