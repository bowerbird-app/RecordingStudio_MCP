# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class McpHandlerGuardTest < ActionDispatch::IntegrationTest
  include OauthDummyHelpers
  include Devise::Test::IntegrationHelpers

  SCOPE_MISS = "Resource was not found in this API scope"

  setup do
    @user = create_user
    @root_recording, = create_access_recording_for(user: @user)
    @viewer = create_user(email: "viewer-#{SecureRandom.hex(4)}@example.com")
    @editor = create_user(email: "editor-#{SecureRandom.hex(4)}@example.com")
    @view_access = grant_role!(@viewer, "view")
    @edit_access = grant_role!(@editor, "edit")
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client(name: "Handler guard MCP")
    @page = record_page("Home")
    @trashed = record_page("Gone")
    @trashed.update_column(:trashed_at, Time.current)
    @folder = record_child(Folder.create!(name: "Notes"), parent: @root_recording)
    outsider = create_user(email: "outsider-#{SecureRandom.hex(4)}@example.com")
    foreign_root, = create_access_recording_for(user: outsider, workspace_name: "Foreign #{SecureRandom.hex(4)}")
    @foreign = record_child(Page.create!(title: "Foreign"), parent: foreign_root, root: foreign_root, actor: outsider)
    @called = false
    @seen = nil
    enable_page_actions(:guard_probe, :guard_read)
  end

  teardown do
    clear_page_handlers(:show, :update, :guard_probe, :guard_read)
    clear_endpoints(:guard_page, :guard_page_edit, :guard_open)
    clear_actions(:guard_probe, :guard_read)
    restore_page_registration!
    Current.actor = nil if defined?(Current)
  end

  test "custom resource handlers scope the recording and hide guard messages" do
    register_page_handler(:show) { |context| seen_payload(context) }
    register_page_handler(:update) { |context| seen_payload(context) }
    view = view_token
    edit = edit_token

    miss_ids = [nil, "", @foreign.id, @folder.id, @trashed.id]
    miss_ids.each do |id|
      arguments = { type: "Page" }
      arguments[:id] = id unless id.nil?
      assert_tool_miss(view, "show", arguments)
      assert_tool_miss(edit, "update", arguments.merge(title: "Hi"))
    end
    refute @called

    shown = call_tool(view, "show", type: "Page", id: @page.id)
    assert_equal @page.id, shown["id"]
    assert_nil shown["parent_id"]
    assert_equal @page.id, @seen.id

    # A view grant is not offered update, so the handler never runs.
    assert_handler_not_called(view, "update", { type: "Page", id: @page.id, title: "Hi" })
    @called = false
    updated = call_tool(edit, "update", type: "Page", id: @page.id, title: "Hi")
    assert_equal @page.id, updated["id"]
    assert_nil updated["parent_id"]
    assert_equal @page.id, @seen.id
  end

  test "custom capability actions scope the recording and hide guard messages" do
    register_probe_action(:guard_probe, http_verb: :post, required_role: :edit)
    register_page_handler(:guard_probe) { |context| seen_payload(context) }
    view = view_token
    edit = edit_token

    [nil, "", @foreign.id, @folder.id, @trashed.id, @page.id].each do |id|
      assert_tool_miss(view, "capability_action", capability_arguments(id))
    end
    [@foreign.id, @folder.id, @trashed.id, nil, ""].each do |id|
      assert_tool_miss(edit, "capability_action", capability_arguments(id))
    end
    refute @called

    probed = call_tool(edit, "capability_action", **capability_arguments(@page.id))
    assert_equal @page.id, probed["id"]
    assert_equal @page.id, @seen.id
  end

  test "scoped endpoints scope the recording and hide guard messages" do
    register_guard_endpoint(:guard_page, verb: :get, path: "guard-page/:id")
    register_guard_endpoint(:guard_page_edit, verb: :post, path: "guard-page-edit/:id")
    view = view_token
    edit = edit_token

    [nil, "", @foreign.id, @folder.id, @trashed.id].each do |id|
      assert_tool_miss(view, "guard_page", endpoint_arguments(id))
      assert_tool_miss(edit, "guard_page_edit", endpoint_arguments(id))
    end
    assert_tool_miss(view, "guard_page_edit", id: @page.id)
    refute @called

    shown = call_tool(view, "guard_page", id: @page.id)
    assert_equal @page.id, shown["recording_id"]
    assert_equal @page.id, @seen.id

    @called = false
    edited = call_tool(edit, "guard_page_edit", id: @page.id)
    assert_equal @page.id, edited["recording_id"]
    assert_equal @page.id, @seen.id
  end

  test "owns_scoping reads and scope_id false keep recording nil" do
    register_page_handler(:show, owns_scoping: true) { |context| seen_payload(context) }
    register_probe_action(:guard_read, http_verb: :get, required_role: :view, owns_scoping: true)
    register_page_handler(:guard_read, owns_scoping: true) { |context| seen_payload(context) }
    RecordingStudioApi.register_endpoint(
      :guard_open,
      http_verb: :post,
      path: "guard-open/:id",
      scope_id: false,
      handler: lambda { |context|
        @called = true
        @seen = context.recording
        { recording_id: context.recording&.id }
      }
    )
    view = view_token

    shown = call_tool(view, "show", type: "Page", id: @foreign.id)
    assert_nil shown["id"]
    assert_nil @seen

    @seen = :unset
    read = call_tool(view, "capability_action", type: "Page", id: @foreign.id, action: "guard_read")
    assert_nil read["id"]
    assert_nil @seen

    @seen = :unset
    opened = call_tool(view, "guard_open", id: @foreign.id)
    assert_nil opened["recording_id"]
    assert_nil @seen
    assert @called
  end

  private

  def record_page(title)
    record_child(Page.create!(title: title), parent: @root_recording)
  end

  def record_child(recordable, parent:, root: @root_recording, actor: @user)
    Current.actor = actor
    RecordingStudio.record!(
      action: "created",
      recordable: recordable,
      root_recording: root,
      parent_recording: parent,
      actor: actor
    ).recording
  end

  def seen_payload(context)
    @called = true
    @seen = context.recording
    parent = context.parent_recording if context.respond_to?(:parent_recording)
    { json: { id: context.recording&.id, parent_id: parent&.id }, status: :ok }
  end

  def register_page_handler(action, owns_scoping: false, &block)
    RecordingStudioApi.register_resource_handler("Page", action, owns_scoping: owns_scoping, handler: block)
  end

  def grant_role!(actor, role)
    Current.actor = @user
    result = RecordingStudioAccessible.grant_access(
      recording: @root_recording,
      actor: actor,
      role: role,
      manager_actor: @user
    )
    raise result.error unless result.success?

    result.value
  end

  def view_token
    issue_delegated_token(access_recording: @view_access, role: "view")
  end

  def edit_token
    issue_delegated_token(access_recording: @edit_access, role: "edit")
  end

  def register_probe_action(name, http_verb:, required_role:, owns_scoping: false)
    RecordingStudioApi.register_capability_action(
      name,
      capability: :guard_scope,
      http_verb: http_verb,
      required_role: required_role,
      owns_scoping: owns_scoping,
      handler: ->(_context) { { json: { builtin: true } } }
    )
  end

  def register_guard_endpoint(name, verb:, path:)
    RecordingStudioApi.register_endpoint(
      name,
      http_verb: verb,
      path: path,
      recordable_type: "Page",
      handler: lambda { |context|
        @called = true
        @seen = context.recording
        { recording_id: context.recording&.id }
      }
    )
  end

  def capability_arguments(id)
    arguments = { type: "Page", action: "guard_probe" }
    arguments[:id] = id unless id.nil?
    arguments
  end

  def endpoint_arguments(id)
    return {} if id.nil?

    { id: id }
  end

  def enable_page_actions(*names)
    registry = RecordingStudioApi.configuration.fetch_api(:public).recordable_registry
    @page_registrations = registry.instance_variable_get(:@registrations)
    @previous_page = @page_registrations["Page"]
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: names)
  end

  def restore_page_registration!
    return unless @page_registrations && @previous_page

    @page_registrations["Page"] = @previous_page
  end

  def clear_page_handlers(*actions)
    store = RecordingStudioApi.configuration.fetch_api(:public).resource_handler_registry.instance_variable_get(:@handlers)
    actions.each { |action| store&.delete(["Page", action.to_s]) }
  end

  def clear_endpoints(*names)
    store = RecordingStudioApi.configuration.fetch_api(:public).registered_endpoint_registry.instance_variable_get(:@registrations)
    names.each { |name| store&.delete(name.to_s) }
  end

  def clear_actions(*names)
    store = RecordingStudioApi.configuration.action_registry.instance_variable_get(:@registrations)
    names.each { |name| store&.delete(name.to_s) }
  end

  def assert_handler_not_called(token, name, arguments)
    @called = false
    post "/recording_studio_mcp",
         params: rpc("tools/call", name: name, arguments: arguments).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    result = JSON.parse(response.body).fetch("result")
    assert_equal true, result["isError"], response.body
    refute @called
  end

  def assert_tool_miss(token, name, arguments)
    @called = false
    post "/recording_studio_mcp",
         params: rpc("tools/call", name: name, arguments: arguments).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success
    result = JSON.parse(response.body).fetch("result")
    assert_equal true, result["isError"], response.body
    assert_equal SCOPE_MISS, result.dig("content", 0, "text")
    refute_includes result.dig("content", 0, "text"), "does not match"
    refute_includes result.dig("content", 0, "text"), "authorized"
    refute @called
  end

  def call_tool(token, name, **arguments)
    @called = false
    post "/recording_studio_mcp",
         params: rpc("tools/call", name: name, arguments: arguments).to_json,
         headers: json_headers.merge("Authorization" => "Bearer #{token}")

    assert_response :success, response.body
    payload = JSON.parse(response.body)
    assert payload["result"], response.body
    refute payload.dig("result", "isError"), response.body
    assert @called, response.body
    result = payload.fetch("result")
    result["structuredContent"].presence || JSON.parse(result.dig("content", 0, "text"))
  end

  def issue_delegated_token(access_recording:, role:)
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: access_recording,
      role: role,
      pkce: @pkce
    )
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    }
    assert_response :success
    JSON.parse(response.body).fetch("access_token")
  end

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def rpc(method, **params)
    { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }
  end
end
