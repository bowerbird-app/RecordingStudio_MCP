# frozen_string_literal: true

require "test_helper"

class AuthorizedByTest < Minitest::Test
  Person = Struct.new(:id)
  Authorization = Struct.new(:manager_actor)
  Credential = Struct.new(:oauth_authorization)
  Grant = Struct.new(:credential)

  class AcceptingContext
    def initialize(authorized_by: nil, oauth_authorization: nil)
      @authorized_by = authorized_by
      @oauth_authorization = oauth_authorization
    end

    attr_reader :authorized_by, :oauth_authorization
  end

  def setup
    @human = Person.new("user-1")
    @grant = Grant.new(Credential.new(Authorization.new(@human)))
  end

  def teardown
    RecordingStudioMcp::AuthorizedBy.leave while RecordingStudioMcp::AuthorizedBy.depth.positive?
  end

  def test_current_api_contexts_ignore_the_handoff
    [
      RecordingStudioApi::ResourceOperationContext,
      RecordingStudioApi::ActionContext,
      RecordingStudioApi::RegisteredEndpointContext
    ].each do |context_class|
      assert_equal({}, RecordingStudioMcp::AuthorizedBy.context_keywords(context_class, @grant))
    end
  end

  def test_handoff_includes_the_human_when_the_context_accepts_it
    keywords = RecordingStudioMcp::AuthorizedBy.context_keywords(AcceptingContext, @grant)

    assert_equal @human, keywords[:authorized_by]
    assert_equal @human, keywords[:oauth_authorization].manager_actor
  end

  def test_api_credential_without_an_authorization_has_no_human
    grant = Grant.new(Object.new)

    assert_nil RecordingStudioMcp::AuthorizedBy.human_for(grant)
    assert_nil RecordingStudioMcp::AuthorizedBy.context_keywords(AcceptingContext, grant)[:authorized_by]
  end

  def test_record_hook_stamps_the_authorizing_human_without_touching_the_actor
    metadata = { api_action: "move" }
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    RecordingStudio::Hooks.run(
      :before_record,
      action: "updated",
      actor: "oauth-client",
      impersonator: nil,
      metadata: metadata
    )

    assert_equal "move", metadata[:api_action]
    assert_equal "AuthorizedByTest::Person", metadata["authorized_by_type"]
    assert_equal "user-1", metadata["authorized_by_id"]
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_record_hook_keeps_authorized_by_already_on_the_event
    metadata = { "authorized_by_type" => "Kept", "authorized_by_id" => "kept-id" }
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    RecordingStudio::Hooks.run(:before_record, actor: "oauth-client", metadata: metadata)

    assert_equal "Kept", metadata["authorized_by_type"]
    assert_equal "kept-id", metadata["authorized_by_id"]
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
  end

  def test_record_hook_is_a_no_op_outside_a_tool_call
    metadata = {}
    RecordingStudioMcp::AuthorizedBy.install!
    RecordingStudio::Hooks.run(:before_record, actor: "oauth-client", metadata: metadata)

    assert_equal({}, metadata)
  end

  def test_leave_restores_the_previous_human
    outer = Grant.new(Credential.new(Authorization.new(Person.new("outer"))))
    RecordingStudioMcp::AuthorizedBy.enter(outer)
    RecordingStudioMcp::AuthorizedBy.enter(@grant)
    assert_equal @human, RecordingStudioMcp::AuthorizedBy.current_human

    RecordingStudioMcp::AuthorizedBy.leave
    assert_equal "outer", RecordingStudioMcp::AuthorizedBy.current_human.id
  ensure
    RecordingStudioMcp::AuthorizedBy.leave
    RecordingStudioMcp::AuthorizedBy.leave
  end
end
